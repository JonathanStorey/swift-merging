#if canImport(SwiftData)
import CloudKit
import CoreData
import Foundation
import Observation
import SwiftData

/// What CloudKit is doing for one container's stores, for views to watch.
///
/// It listens to `NSPersistentCloudKitContainer.eventChangedNotification`, which CloudKit posts for SwiftData
/// stores too, and to the iCloud account. There's no public way to start a sync, so it offers the honest
/// alternatives: a save starts an export, and the `wait` methods return once CloudKit confirms the work.
///
/// Get one from `container.syncMonitor` or `context.syncMonitor`, which keep one per container.
@MainActor
@Observable
public final class SyncMonitor {
    /// What CloudKit is busy with.
    public enum Activity: Sendable, Equatable {
        case idle
        case settingUp
        case importing
        case exporting
    }

    public let container: ModelContainer

    /// What CloudKit is doing now. An export shows over an import when both are running.
    public private(set) var activity: Activity = .idle
    /// When an import last finished successfully.
    public private(set) var lastImport: Date?
    /// When an export last finished successfully.
    public private(set) var lastExport: Date?
    /// The latest problem, until the same kind of work next succeeds.
    public private(set) var problem: SyncProblem?
    /// The iCloud account's state, when a CloudKit container is known.
    public private(set) var accountStatus: AccountStatus = .unknown
    /// How many objects are saved but not yet confirmed uploaded.
    public private(set) var pendingUploadCount = 0
    /// Whether CloudKit has been seen syncing these stores, in this launch or an earlier one.
    public private(set) var isSyncing = false
    /// The latest finished events, newest last, up to 50.
    public private(set) var recentEvents: [SyncEvent] = []

    /// The CloudKit container whose account status it checks.
    public let cloudKitContainerIdentifier: String?

    @ObservationIgnored private var running: [UUID: SyncEvent.Kind] = [:]
    @ObservationIgnored private var problemKind: SyncEvent.Kind?
    @ObservationIgnored private var storeIdentifiers: Set<String> = []
    @ObservationIgnored private let ledger: SyncLedger
    @ObservationIgnored private let observers = ObserverTokens()

    /// A monitor of `container`'s stores, which checks the account of `cloudKitContainerIdentifier`, or of
    /// the first container its configurations name.
    public init(container: ModelContainer, cloudKitContainerIdentifier: String? = nil) {
        self.container = container
        self.cloudKitContainerIdentifier = cloudKitContainerIdentifier
            ?? container.configurations.compactMap(\.cloudKitContainerIdentifier).sorted().first
        ledger = .shared
        refreshStoreIdentifiers()
        refreshFromLedger()
        startObserving()
        refreshAccountStatus()
    }

    init(container: ModelContainer, ledger: SyncLedger, observes: Bool) {
        self.container = container
        cloudKitContainerIdentifier = nil
        self.ledger = ledger
        refreshStoreIdentifiers()
        refreshFromLedger()
        if observes { startObserving() }
    }

    // MARK: - Waiting

    /// Waits for an export that starts after `date` to finish. A save starts one if it changed anything that
    /// syncs, so call it just after saving, passing a date from just before.
    public func waitForExport(startedAfter date: Date, timeout: Duration = .seconds(30)) async -> SyncWaitResult {
        await waitForEvent(.export, timeout: timeout) { $0.startDate >= date }
    }

    /// Waits for an import to finish after `date`. CloudKit imports when the app launches or comes to the
    /// foreground, and when a push says the server changed, so this can time out when nothing changed.
    public func waitForImport(finishedAfter date: Date = .now, timeout: Duration = .seconds(30)) async -> SyncWaitResult {
        await waitForEvent(.import, timeout: timeout) { ($0.endDate ?? .distantPast) >= date }
    }

    /// Waits for every object waiting to upload to be confirmed, then for an import to finish, so this
    /// device has sent what it has and taken what the server had at the time.
    public func waitForSync(timeout: Duration = .seconds(60)) async -> SyncWaitResult {
        let start = Date.now
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        guard isSyncing else { return .notSyncing }
        while ledger.pendingCount(inStores: storeIdentifiers) > 0 {
            if let failure = lastingFailure(.export, since: start) { return .failed(failure) }
            guard clock.now < deadline, await pause() else {
                return .timedOut(waiting: ledger.pendingCount(inStores: storeIdentifiers))
            }
        }
        return await waitForImport(finishedAfter: start, timeout: clock.now.duration(to: deadline))
    }

    /// Waits until CloudKit confirms the server has each of `models` as saved at `date` or later.
    public func waitForUpload(of models: [any PersistentModel], savedAt date: Date,
                              timeout: Duration = .seconds(60)) async -> SyncWaitResult {
        let keys = models.compactMap { StoreRecords.key(of: $0.persistentModelID) }
        return await waitForUpload(ofKeys: keys, savedAt: date, timeout: timeout)
    }

    func waitForUpload(ofKeys keys: [String], savedAt date: Date, timeout: Duration) async -> SyncWaitResult {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while true {
            let statuses = keys.map(ledger.status(ofKey:))
            let waiting = statuses.filter { status in
                if case .synced(let at) = status { return at < date }
                return true
            }
            if waiting.isEmpty { return .completed }
            if let failure = lastingFailure(.export, since: date) { return .failed(failure) }
            guard clock.now < deadline, await pause() else {
                return waiting.allSatisfy { $0 == .localOnly } ? .notSyncing : .timedOut(waiting: waiting.count)
            }
        }
    }

    private func waitForEvent(_ kind: SyncEvent.Kind, timeout: Duration, where matches: (SyncEvent) -> Bool) async -> SyncWaitResult {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while true {
            for event in recentEvents where event.kind == kind && matches(event) {
                if event.succeeded { return .completed }
                if let problem = event.problem, !problem.isTransient { return .failed(problem) }
            }
            guard clock.now < deadline, await pause() else { return isSyncing ? .timedOut(waiting: 0) : .notSyncing }
        }
    }

    /// A failure of `kind` since `date` that CloudKit won't fix by retrying.
    private func lastingFailure(_ kind: SyncEvent.Kind, since date: Date) -> SyncProblem? {
        recentEvents.last { $0.kind == kind && $0.startDate >= date && !$0.succeeded && $0.problem?.isTransient == false }?.problem
    }

    /// Sleeps briefly, returning `false` if the task was cancelled.
    private func pause() async -> Bool {
        try? await Task.sleep(for: .milliseconds(200))
        return !Task.isCancelled
    }

    // MARK: - Events

    /// Takes in one CloudKit event for the store `store`.
    func record(_ event: SyncEvent, id: UUID, store: String) {
        if storeIdentifiers.isEmpty { refreshStoreIdentifiers() }
        guard storeIdentifiers.isEmpty || storeIdentifiers.contains(store) else { return }
        isSyncing = true
        if event.isFinished {
            running[id] = nil
            recentEvents.append(event)
            if recentEvents.count > 50 { recentEvents.removeFirst(recentEvents.count - 50) }
            if event.succeeded {
                switch event.kind {
                case .import: lastImport = event.endDate
                case .export: lastExport = event.endDate
                case .setup: break
                }
                if problemKind == event.kind {
                    problem = nil
                    problemKind = nil
                }
            } else if let eventProblem = event.problem {
                problem = eventProblem
                problemKind = event.kind
                if eventProblem == .notSignedIn { refreshAccountStatus() }
            }
        } else {
            running[id] = event.kind
        }
        let kinds = Set(running.values)
        activity = kinds.contains(.export) ? .exporting : kinds.contains(.import) ? .importing
            : kinds.contains(.setup) ? .settingUp : .idle
        refreshFromLedger()
    }

    private func refreshFromLedger() {
        let count = ledger.pendingCount(inStores: storeIdentifiers)
        if pendingUploadCount != count { pendingUploadCount = count }
        if !isSyncing, storeIdentifiers.contains(where: ledger.isCloudStore) { isSyncing = true }
    }

    private func refreshStoreIdentifiers() {
        storeIdentifiers = Set(container.configurations.compactMap { StoreRecords.storeIdentifier(at: $0.url) })
    }

    private func refreshAccountStatus() {
        guard let identifier = cloudKitContainerIdentifier else { return }
        Task { [weak self] in
            let status: AccountStatus
            do {
                status = AccountStatus(try await CKContainer(identifier: identifier).accountStatus())
            } catch {
                status = .couldNotDetermine
            }
            self?.accountStatus = status
        }
    }

    private func startObserving() {
        let center = NotificationCenter.default
        observers.add(center.addObserver(forName: NSPersistentCloudKitContainer.eventChangedNotification, object: nil, queue: nil) { [weak self] note in
            guard let event = note.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey] as? NSPersistentCloudKitContainer.Event,
                  let snapshot = SyncEvent(event) else { return }
            let id = event.identifier, store = event.storeIdentifier
            let monitor = self
            Task { @MainActor in monitor?.record(snapshot, id: id, store: store) }
        })
        observers.add(center.addObserver(forName: SyncLedger.didChange, object: nil, queue: nil) { [weak self] _ in
            let monitor = self
            Task { @MainActor in monitor?.refreshFromLedger() }
        })
        observers.add(center.addObserver(forName: .CKAccountChanged, object: nil, queue: nil) { [weak self] _ in
            let monitor = self
            Task { @MainActor in monitor?.refreshAccountStatus() }
        })
    }
}

extension SyncEvent {
    /// A CloudKit event, or `nil` for a kind it doesn't know.
    init?(_ event: NSPersistentCloudKitContainer.Event) {
        switch event.type {
        case .setup: kind = .setup
        case .import: kind = .import
        case .export: kind = .export
        @unknown default: return nil
        }
        startDate = event.startDate
        endDate = event.endDate
        succeeded = event.succeeded
        problem = event.error.map(SyncProblem.init)
    }
}

/// Notification observers, removed when it goes away.
final class ObserverTokens: @unchecked Sendable {
    private let lock = NSLock()
    private var tokens: [any NSObjectProtocol] = []

    func add(_ token: any NSObjectProtocol) {
        lock.synchronized { tokens.append(token) }
    }

    deinit {
        for token in tokens { NotificationCenter.default.removeObserver(token) }
    }
}

@MainActor private var monitors: [ObjectIdentifier: SyncMonitor] = [:]

extension ModelContainer {
    /// The container's sync monitor, made the first time it's asked for and kept as long as the app runs.
    /// Asking for it early, such as where the container is made, also starts tracking each object's status.
    @MainActor
    public var syncMonitor: SyncMonitor {
        if let monitor = monitors[ObjectIdentifier(self)] { return monitor }
        let monitor = SyncMonitor(container: self)
        monitors[ObjectIdentifier(self)] = monitor
        return monitor
    }
}
#endif
