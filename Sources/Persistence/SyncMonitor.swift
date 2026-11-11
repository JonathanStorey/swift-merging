#if canImport(SwiftData)
import CloudKit
import CoreData
import Foundation
import Observation
import SwiftData

/// What CloudKit is doing for one container's stores, for views to watch and code to wait on.
///
/// There's one per container, since CloudKit syncs each store on its own and every context on a container
/// shares its stores: `container.sync` and `context.sync` are the same object. Read it at launch, which
/// also starts tracking each object's `syncStatus`.
///
/// It listens to `NSPersistentCloudKitContainer.eventChangedNotification`, which CloudKit posts for SwiftData
/// stores too, and to the iCloud account. There's no public way to start a sync, so it offers the honest
/// alternative: a save starts an upload, and `wait(for:)` returns once CloudKit confirms it.
@MainActor
@Observable
public final class SyncMonitor {
    /// What CloudKit is doing.
    public enum Activity: Sendable, Hashable {
        /// CloudKit hasn't been seen syncing these stores.
        case off
        case idle
        case preparing
        case downloading
        case uploading
    }

    public let container: ModelContainer

    /// What CloudKit is doing now. An upload shows over a download when both are running.
    public private(set) var activity: Activity = .off
    /// How many saved objects the server hasn't confirmed yet.
    public private(set) var pending = 0
    /// The latest failure, until the same kind of work next succeeds.
    public private(set) var error: SyncError?
    /// The iCloud account's state. It reads `.couldNotDetermine` until checked, or when no CloudKit
    /// container is known to check.
    public private(set) var account: CKAccountStatus = .couldNotDetermine
    /// When an upload or download last finished successfully.
    public private(set) var lastSynced: Date?

    /// Every CloudKit event for these stores from now on, as it starts and finishes.
    public var events: AsyncStream<SyncEvent> {
        let (stream, continuation) = AsyncStream.makeStream(of: SyncEvent.self)
        let id = UUID()
        continuations[id] = continuation
        continuation.onTermination = { [weak self] _ in
            let monitor = self
            Task { @MainActor in monitor?.continuations[id] = nil }
        }
        return stream
    }

    @ObservationIgnored private var isEnabled = false
    @ObservationIgnored private var running: [UUID: SyncEvent.Kind] = [:]
    @ObservationIgnored private var errorKind: SyncEvent.Kind?
    @ObservationIgnored private(set) var finished: [SyncEvent] = []
    @ObservationIgnored private var continuations: [UUID: AsyncStream<SyncEvent>.Continuation] = [:]
    @ObservationIgnored private var storeIdentifiers: Set<String> = []
    private let cloudKitContainerIdentifier: String?
    private let ledger: SyncLedger
    private let observers = ObserverTokens()

    init(container: ModelContainer, ledger: SyncLedger = .shared, observes: Bool = true) {
        self.container = container
        self.ledger = ledger
        cloudKitContainerIdentifier = observes
            ? container.configurations.compactMap(\.cloudKitContainerIdentifier).sorted().first : nil
        refreshStoreIdentifiers()
        refreshFromLedger()
        if observes { startObserving() }
        refreshAccount()
    }

    // MARK: - Waiting

    /// Waits until the server has `model` as this device last saved it.
    public func wait(for model: some PersistentModel, timeout: Duration = .seconds(60)) async throws {
        try await wait(for: [model], timeout: timeout)
    }

    /// Waits until the server has every one of `models` as this device last saved them.
    public func wait(for models: [any PersistentModel], timeout: Duration = .seconds(60)) async throws {
        let keys = models.compactMap { StoreRecords.key(of: $0.persistentModelID) }
        try await wait(forKeys: keys, savedAt: nil, timeout: timeout)
    }

    /// Waits for the next upload or download to finish. An upload must start after the call, since one
    /// already running may not carry what was just saved. CloudKit downloads at launch, on returning to
    /// the foreground, and on a push, so a download wait can time out when nothing changed.
    public func wait(for direction: SyncDirection, timeout: Duration = .seconds(60)) async throws {
        try await wait(for: direction, after: .now, timeout: timeout)
    }

    /// Waits until everything waiting to upload is confirmed, then for a download to finish, so this
    /// device has sent what it has and taken what the server had.
    public func wait(timeout: Duration = .seconds(60)) async throws {
        let start = Date.now
        let deadline = ContinuousClock.now.advanced(by: timeout)
        guard isEnabled else { throw SyncError.notEnabled }
        while ledger.pendingCount(inStores: storeIdentifiers) > 0 {
            if let failure = lastingFailure(.upload, since: start) { throw failure }
            try await pause(until: deadline)
        }
        try await wait(for: .download, after: start, timeout: ContinuousClock.now.duration(to: deadline))
    }

    func wait(for direction: SyncDirection, after date: Date, timeout: Duration) async throws {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        let kind = direction.eventKind
        while true {
            for event in finished where event.kind == kind {
                let matches = direction == .upload ? event.startDate >= date : (event.endDate ?? .distantPast) >= date
                guard matches else { continue }
                if event.succeeded { return }
                if let error = event.error, !error.isTransient { throw error }
            }
            do {
                try await pause(until: deadline)
            } catch SyncError.timedOut where !isEnabled {
                throw SyncError.notEnabled
            }
        }
    }

    /// Waits until each object is synced, at `savedAt` or later when given.
    func wait(forKeys keys: [String], savedAt date: Date?, timeout: Duration) async throws {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        let since = date ?? .now
        while true {
            let waiting = keys.map(ledger.status(ofKey:)).filter { status in
                if case .synced(let at) = status { return date.map { at < $0 } ?? false }
                return true
            }
            if waiting.isEmpty { return }
            if let failure = lastingFailure(.upload, since: since) { throw failure }
            do {
                try await pause(until: deadline)
            } catch SyncError.timedOut where waiting.allSatisfy({ $0 == .localOnly }) {
                throw SyncError.notEnabled
            }
        }
    }

    /// A failure of `kind` since `date` that CloudKit won't fix by retrying.
    private func lastingFailure(_ kind: SyncEvent.Kind, since date: Date) -> SyncError? {
        finished.last { $0.kind == kind && $0.startDate >= date && !$0.succeeded && $0.error?.isTransient == false }?.error
    }

    /// Sleeps briefly, throwing `SyncError.timedOut` past `deadline`, or `CancellationError`.
    private func pause(until deadline: ContinuousClock.Instant) async throws {
        guard ContinuousClock.now < deadline else { throw SyncError.timedOut }
        try await Task.sleep(for: .milliseconds(200))
    }

    // MARK: - Events

    /// Takes in one CloudKit event for the store `store`.
    func record(_ event: SyncEvent, id: UUID, store: String) {
        if storeIdentifiers.isEmpty { refreshStoreIdentifiers() }
        guard storeIdentifiers.isEmpty || storeIdentifiers.contains(store) else { return }
        isEnabled = true
        if event.isFinished {
            running[id] = nil
            finished.append(event)
            if finished.count > 100 { finished.removeFirst(finished.count - 100) }
            if event.succeeded {
                if event.kind != .setup, let end = event.endDate, end > lastSynced ?? .distantPast { lastSynced = end }
                if errorKind == event.kind {
                    error = nil
                    errorKind = nil
                }
            } else if let eventError = event.error {
                error = eventError
                errorKind = event.kind
                if eventError == .notSignedIn { refreshAccount() }
            }
        } else {
            running[id] = event.kind
        }
        for continuation in continuations.values { continuation.yield(event) }
        refreshActivity()
        refreshFromLedger()
    }

    private func refreshActivity() {
        let kinds = Set(running.values)
        let new: Activity = !isEnabled ? .off : kinds.contains(.upload) ? .uploading : kinds.contains(.download) ? .downloading
            : kinds.contains(.setup) ? .preparing : .idle
        if activity != new { activity = new }
    }

    private func refreshFromLedger() {
        let count = ledger.pendingCount(inStores: storeIdentifiers)
        if pending != count { pending = count }
        if !isEnabled, storeIdentifiers.contains(where: ledger.isCloudStore) {
            isEnabled = true
            refreshActivity()
        }
    }

    private func refreshStoreIdentifiers() {
        storeIdentifiers = Set(container.configurations.compactMap { StoreRecords.storeIdentifier(at: $0.url) })
    }

    private func refreshAccount() {
        guard let identifier = cloudKitContainerIdentifier else { return }
        Task { [weak self] in
            let status = (try? await CKContainer(identifier: identifier).accountStatus()) ?? .couldNotDetermine
            self?.account = status
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
            Task { @MainActor in monitor?.refreshAccount() }
        })
    }
}

extension SyncEvent {
    /// A CloudKit event, or `nil` for a kind it doesn't know.
    init?(_ event: NSPersistentCloudKitContainer.Event) {
        switch event.type {
        case .setup: kind = .setup
        case .import: kind = .download
        case .export: kind = .upload
        @unknown default: return nil
        }
        startDate = event.startDate
        endDate = event.endDate
        succeeded = event.succeeded
        error = event.error.map(SyncError.init)
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
    /// The container's sync monitor, made the first time it's read and kept as long as the app runs.
    /// Reading it at launch also starts tracking each object's `syncStatus`.
    @MainActor
    public var sync: SyncMonitor {
        if let monitor = monitors[ObjectIdentifier(self)] { return monitor }
        let monitor = SyncMonitor(container: self)
        monitors[ObjectIdentifier(self)] = monitor
        return monitor
    }
}
#endif
