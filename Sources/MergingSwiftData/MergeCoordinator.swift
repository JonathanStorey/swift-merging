#if canImport(SwiftData)
import CoreData
import Foundation
import Merging
import SwiftData

/// Merges other contexts', processes', and devices' saves into this device's edits, property by property,
/// by reading the store's history.
///
/// For each object someone else changed it takes three snapshots: the base, ours, and theirs, which is
/// what's in the store now.
///
/// - **Another context or process** saved: the base is the object as stored just before that save, which
///   the store reports as it saves (see `StoreChangeCapture`), or failing that the ledger's base. Ours is
///   the main context's unsaved edits, and the merge goes back into the main context's object, so its next
///   save writes it. An object the main context hasn't edited needs nothing.
/// - **A sync service imported** a change, such as CloudKit: the other device started from the agreed
///   base, so that's the base. Ours is this device's saved object as it was before the import, and the
///   merge is written back to the store as this device's own edit, ready to export. Unsaved edits in the
///   main context then merge on top of it.
///
/// ```swift
/// let container = try ModelContainer(for: Note.self)
/// try container.enableMerging(Note.self)
/// ```
///
/// It runs on the main actor, beside the main context it merges into.
@available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
@MainActor
public final class MergeCoordinator {
    /// The author of the main context's saves, and of the merges this writes, which marks them as ours in
    /// the history. Any other author's save, or one with no author, is theirs.
    public static let localAuthor = "Merging.local"

    /// The author CloudKit gives the transactions it imports.
    public static let cloudKitImportAuthor = "NSCloudKitMirroringDelegate.import"

    public let container: ModelContainer
    public let ledger: any MergeLedger
    public let conflictPolicy: MergeConflictPolicy
    /// What a property without `@Merge` does.
    public let unmergedProperties: UnmergedPropertyPolicy
    /// The authors whose saves are imports from a sync service.
    public let importAuthors: Set<String>

    let capture: StoreChangeCapture
    private let handlers: [any ModelMergeHandler]
    private var isMerging = false
    private nonisolated(unsafe) var observers: [any NSObjectProtocol] = []

    /// A coordinator for `types` in `container`. It sets the main context's author, starts noting the
    /// store's saves, and with a ledger that has no token yet it reads every object's base from the store.
    public init(container: ModelContainer, types: [any MergeableModel.Type], ledger: (any MergeLedger)? = nil,
                conflictPolicy: MergeConflictPolicy = .storeDefault,
                unmergedProperties: UnmergedPropertyPolicy = .followSwiftData,
                importAuthors: Set<String> = [MergeCoordinator.cloudKitImportAuthor]) throws {
        self.container = container
        self.ledger = ledger ?? InMemoryMergeLedger()
        self.conflictPolicy = conflictPolicy
        self.unmergedProperties = unmergedProperties
        self.importAuthors = importAuthors
        handlers = types.map { makeHandler(for: $0) }
        capture = StoreChangeCapture(storeURL: container.configurations.first?.url, ignoredAuthors: [Self.localAuthor])
        capture.start()
        container.mainContext.author = Self.localAuthor
        if self.ledger.token == nil { try seed() }
    }

    deinit {
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
    }

    /// Merges every transaction saved since the last pass. Merging is idempotent, so an extra call costs
    /// one history fetch.
    public func mergePendingChanges() throws {
        guard !isMerging else { return }
        isMerging = true
        defer { isMerging = false }

        // Saves that finished before the history fetch are certainly in it.
        let finished = capture.completedSequences()
        let reader = ModelContext(container)
        var descriptor = HistoryDescriptor<DefaultHistoryTransaction>()
        if let token = ledger.token {
            descriptor.predicate = #Predicate { $0.token > token }
        }
        let transactions = try reader.fetchHistory(descriptor)
        guard !transactions.isEmpty else { return }

        let writer = ModelContext(container)
        writer.author = Self.localAuthor
        writer.autosaveEnabled = false
        let pass = MergePass(reader: reader, main: container.mainContext, writer: writer, ledger: ledger,
                             conflictPolicy: conflictPolicy, keepsChanges: unmergedProperties.keepsChanges,
                             capture: capture, finished: finished)
        for transaction in transactions {
            let source: ChangeSource
            if transaction.author == Self.localAuthor {
                source = .local
            } else if let author = transaction.author, importAuthors.contains(author) {
                source = .import
            } else {
                source = .other
            }
            for change in transaction.changes {
                for handler in handlers {
                    try handler.handle(change, from: source, at: transaction.timestamp, in: pass)
                }
            }
            ledger.token = transaction.token
        }
        for handler in handlers {
            try handler.mergeUpdates(in: pass)
        }
        // Merges of imports this device hadn't edited, saved as its own edits; the next pass reads them.
        if writer.hasChanges { try writer.save() }
        try ledger.save()
    }

    /// Tells the coordinator a sync service started or finished work. A finished import merges what it
    /// brought, and a finished export makes what it sent the agreed base. With CloudKit, `startObserving()`
    /// calls this for each of the container's events, so there's no need to call it yourself; another sync
    /// engine can.
    public func syncEventOccurred(_ event: MergeSyncEvent) {
        guard event.endDate != nil else { return }
        mergeQuietly()
        if event.kind == .export, event.succeeded {
            ledger.promoteLocalSaves(through: event.startDate)
            try? ledger.save()
        }
    }

    /// Merges on its own from now on: just before and just after the main context saves, so a save never
    /// writes over theirs and the next base is what it saved; soon after any other context saves; and when
    /// CloudKit finishes an import or export.
    public func startObserving() {
        guard observers.isEmpty else { return }
        let main = container.mainContext
        let mainID = ObjectIdentifier(main)
        let center = NotificationCenter.default

        // The main context posts on the main thread, and the merge has to land before its save goes on.
        for name in [ModelContext.willSave, ModelContext.didSave] {
            observers.append(center.addObserver(forName: name, object: main, queue: nil) { [weak self] _ in
                guard Thread.isMainThread else { return }
                MainActor.assumeIsolated { self?.mergeQuietly() }
            })
        }
        // Any other context, on any thread: merge on the main actor once it's free.
        observers.append(center.addObserver(forName: ModelContext.didSave, object: nil, queue: nil) { [weak self] note in
            guard let sender = note.object as AnyObject?, ObjectIdentifier(sender) != mainID else { return }
            let coordinator = self
            Task { @MainActor in coordinator?.mergeQuietly() }
        })
        // CloudKit's own progress, for this container's store.
        let capture = capture
        observers.append(center.addObserver(forName: NSPersistentCloudKitContainer.eventChangedNotification, object: nil, queue: nil) { [weak self] note in
            guard let event = note.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey] as? NSPersistentCloudKitContainer.Event,
                  let syncEvent = MergeSyncEvent(event) else { return }
            let stores = capture.storeIdentifiers
            guard stores.isEmpty || stores.contains(event.storeIdentifier) else { return }
            let coordinator = self
            Task { @MainActor in coordinator?.syncEventOccurred(syncEvent) }
        })
    }

    /// Stops merging on its own.
    public func stopObserving() {
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers = []
    }

    private func mergeQuietly() {
        do {
            try mergePendingChanges()
        } catch {
            // Silent by design: the next pass starts from the same token and tries again.
        }
    }

    /// Reads every object's base, and the token they're current to. What's in the store is taken as agreed.
    private func seed() throws {
        let reader = ModelContext(container)
        ledger.token = try reader.fetchHistory(HistoryDescriptor<DefaultHistoryTransaction>()).last?.token
        for handler in handlers {
            try handler.seed(ledger, from: reader)
        }
        try ledger.save()
    }
}

/// A sync service's work starting or finishing, such as a CloudKit import or export.
public struct MergeSyncEvent: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        case setup
        case `import`
        case export
    }

    public var kind: Kind
    public var startDate: Date
    /// When it finished, or `nil` while it's running.
    public var endDate: Date?
    public var succeeded: Bool

    public init(kind: Kind, startDate: Date, endDate: Date?, succeeded: Bool) {
        self.kind = kind
        self.startDate = startDate
        self.endDate = endDate
        self.succeeded = succeeded
    }

    /// A CloudKit event, or `nil` for a kind it doesn't know.
    public init?(_ event: NSPersistentCloudKitContainer.Event) {
        switch event.type {
        case .setup: kind = .setup
        case .import: kind = .import
        case .export: kind = .export
        @unknown default: return nil
        }
        startDate = event.startDate
        endDate = event.endDate
        succeeded = event.succeeded
    }
}

@available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
extension ModelContainer {
    /// Merges `types` property by property from now on, and keeps the coordinator alive as long as the
    /// container. Call it once, after making the container.
    @discardableResult
    @MainActor
    public func enableMerging(_ types: any MergeableModel.Type..., ledger: (any MergeLedger)? = nil,
                              conflictPolicy: MergeConflictPolicy = .storeDefault,
                              unmergedProperties: UnmergedPropertyPolicy = .followSwiftData) throws -> MergeCoordinator {
        let coordinator = try MergeCoordinator(container: self, types: types, ledger: ledger, conflictPolicy: conflictPolicy,
                                               unmergedProperties: unmergedProperties)
        coordinator.startObserving()
        activeCoordinators[ObjectIdentifier(self)] = coordinator
        return coordinator
    }
}

@MainActor private var activeCoordinators: [ObjectIdentifier: AnyObject] = [:]

/// Who saved a transaction, in the order a pass weighs them: an object changed by several in one pass is
/// merged as the last of them would be.
enum ChangeSource: Int, Comparable {
    /// The main context, or a merge this wrote.
    case local = 0
    /// Another context or process on this device.
    case other = 1
    /// A sync service, bringing another device's change.
    case `import` = 2

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// An object's updates in one pass.
struct PassUpdate {
    var source: ChangeSource
    /// When the latest was saved.
    var date: Date
    /// The model type it belongs to.
    var model: ObjectIdentifier
}

/// What one pass over the history shares among the models it merges.
@available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
@MainActor
final class MergePass {
    /// A fresh context, so it reads what's in the store.
    let reader: ModelContext
    let main: ModelContext
    /// Where merges of imports are written, as this device's edits.
    let writer: ModelContext
    let ledger: any MergeLedger
    let conflictPolicy: MergeConflictPolicy
    /// Whether a property without a strategy keeps the side that changed it.
    let keepsChanges: Bool
    let capture: StoreChangeCapture
    /// The captured saves that finished before the history fetch.
    let finished: Set<Int>
    /// The objects updated in this pass, merged once each at its end: the store holds only the last of
    /// their values, so that's what every update merges with.
    var updates: [PersistentIdentifier: PassUpdate] = [:]

    init(reader: ModelContext, main: ModelContext, writer: ModelContext, ledger: any MergeLedger,
         conflictPolicy: MergeConflictPolicy, keepsChanges: Bool, capture: StoreChangeCapture, finished: Set<Int>) {
        self.reader = reader
        self.main = main
        self.writer = writer
        self.ledger = ledger
        self.conflictPolicy = conflictPolicy
        self.keepsChanges = keepsChanges
        self.capture = capture
        self.finished = finished
    }
}

/// Merges one model type's changes.
@available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
@MainActor
protocol ModelMergeHandler {
    func seed(_ ledger: any MergeLedger, from reader: ModelContext) throws
    func handle(_ change: HistoryChange, from source: ChangeSource, at date: Date, in pass: MergePass) throws
    func mergeUpdates(in pass: MergePass) throws
}

@available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
@MainActor
private func makeHandler<Model: MergeableModel>(for type: Model.Type) -> any ModelMergeHandler {
    ModelHandler<Model>()
}

@available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
@MainActor
struct ModelHandler<Model: MergeableModel>: ModelMergeHandler {
    typealias Snapshot = Model.MergeSnapshot

    func seed(_ ledger: any MergeLedger, from reader: ModelContext) throws {
        for model in try reader.fetch(FetchDescriptor<Model>()) {
            let data = try JSONEncoder().encode(model.mergeSnapshot)
            ledger.setBase(data, for: model.persistentModelID)
            ledger.setAgreedBase(data, for: model.persistentModelID)
        }
    }

    func handle(_ change: HistoryChange, from source: ChangeSource, at date: Date, in pass: MergePass) throws {
        let id = change.changedPersistentIdentifier
        switch change {
        case .insert(let insert):
            guard insert is DefaultHistoryInsert<Model>, let saved = try fetch(id, in: pass.reader) else { return }
            let snapshot = try JSONEncoder().encode(saved.mergeSnapshot)
            pass.ledger.setBase(snapshot, for: id)
            if source == .import {
                pass.ledger.setAgreedBase(snapshot, for: id)
            } else {
                pass.ledger.recordLocalSave(snapshot, for: id, at: date)
            }
        case .delete(let delete):
            guard delete is DefaultHistoryDelete<Model> else { return }
            pass.updates[id] = nil
            pass.ledger.setBase(nil, for: id)
            pass.ledger.setAgreedBase(nil, for: id)
            pass.capture.discard(object: MergeRelationship.key(id))
        case .update(let update):
            guard let update = update as? DefaultHistoryUpdate<Model>, touchesMergedProperty(update) else { return }
            let earlier = pass.updates[id]
            pass.updates[id] = PassUpdate(source: max(earlier?.source ?? source, source), date: date, model: ObjectIdentifier(Model.self))
        @unknown default:
            return
        }
    }

    func mergeUpdates(in pass: MergePass) throws {
        for (id, update) in pass.updates where update.model == ObjectIdentifier(Model.self) {
            guard let saved = try fetch(id, in: pass.reader) else { continue }
            try merge(id, theirs: saved.mergeSnapshot, from: update.source, at: update.date, in: pass)
        }
    }

    private func merge(_ id: PersistentIdentifier, theirs: Snapshot, from source: ChangeSource, at date: Date, in pass: MergePass) throws {
        let ledgerBase = try decode(pass.ledger.base(for: id))
        // The object as stored before the saves this pass covers: the ledger's base, with what the store
        // reported as it saved in place of every property those saves changed.
        let captured = capturedBase(of: id, theirs: theirs, in: pass)
        let before = captured.isEmpty ? ledgerBase : SnapshotPatch.apply(captured, to: ledgerBase ?? theirs, fallback: ledgerBase)
        let mine: Model? = pass.main.registeredModel(for: id)
        let dirty = mine.flatMap { $0.hasChanges ? $0 : nil }

        switch source {
        case .local:
            pass.ledger.recordLocalSave(try JSONEncoder().encode(theirs), for: id, at: date)

        case .other:
            // The main context's save writes the whole object, so without a merge its edits would win.
            if let base = before, let dirty {
                let ours = dirty.mergeSnapshot
                let merged = Model.mergeSnapshots(base: base, ours: ours, theirs: theirs,
                                                  favoring: pass.conflictPolicy.side(whereStoreKeeps: .ours),
                                                  keepingChanges: pass.keepsChanges)
                if merged != ours { dirty.applyMergeSnapshot(merged) }
            }
            // To a sync service, another context's save is this device's own edit.
            pass.ledger.recordLocalSave(try JSONEncoder().encode(theirs), for: id, at: date)

        case .import:
            // What this device had saved, merged with what the other device saved, from where both started.
            // The import is written last, so without a merge it would win.
            let saved = before ?? theirs
            let agreed = try decode(pass.ledger.agreedBase(for: id))
            let merged = agreed.map {
                Model.mergeSnapshots(base: $0, ours: saved, theirs: theirs, favoring: pass.conflictPolicy.side(whereStoreKeeps: .theirs),
                                     keepingChanges: pass.keepsChanges)
            } ?? theirs
            pass.ledger.setAgreedBase(try JSONEncoder().encode(theirs), for: id)
            if let dirty {
                // Unsaved edits started from what was saved, and merge onto the merged import.
                let ours = dirty.mergeSnapshot
                let final = Model.mergeSnapshots(base: saved, ours: ours, theirs: merged,
                                                 favoring: pass.conflictPolicy.side(whereStoreKeeps: .ours),
                                                 keepingChanges: pass.keepsChanges)
                if final != ours { dirty.applyMergeSnapshot(final) }
            } else if merged != theirs, let target = try fetch(id, in: pass.writer) {
                target.applyMergeSnapshot(merged)
            }
        }
        // The store holds theirs until a merge is saved, which makes a pass of its own.
        pass.ledger.setBase(try JSONEncoder().encode(theirs), for: id)
    }

    /// The stored values, before this pass's saves, of the properties they changed, as the store reported
    /// them. A property two saves changed takes the earlier one's.
    private func capturedBase(of id: PersistentIdentifier, theirs: Snapshot, in pass: MergePass) -> [String: Any] {
        let key = MergeRelationship.key(id)
        // A save is in this pass if it finished before the history fetch, or if the store already holds
        // what it wrote. One that finished later and doesn't match is left for the next pass.
        let covered = pass.capture.records(forObject: key).filter {
            pass.finished.contains($0.sequence) || SnapshotPatch.matches($0.new, theirs)
        }
        guard let last = covered.last else { return [:] }
        pass.capture.discard(object: key, through: last.sequence)
        var values: [String: Any] = [:]
        for record in covered {
            for (property, value) in record.base where values[property] == nil {
                values[property] = value
            }
        }
        return values
    }

    /// Whether an update changed a merged property. An update that names none is taken to change them all.
    private func touchesMergedProperty(_ update: DefaultHistoryUpdate<Model>) -> Bool {
        let merged = Set(Model.mergeKeyPaths)
        return update.updatedAttributes.isEmpty || update.updatedAttributes.contains { merged.contains($0) }
    }

    /// The object in `context`, or `nil` if it's since been deleted.
    private func fetch(_ id: PersistentIdentifier, in context: ModelContext) throws -> Model? {
        var descriptor = FetchDescriptor<Model>(predicate: #Predicate { $0.persistentModelID == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private func decode(_ data: Data?) throws -> Snapshot? {
        guard let data else { return nil }
        return try JSONDecoder().decode(Snapshot.self, from: data)
    }
}
#endif
