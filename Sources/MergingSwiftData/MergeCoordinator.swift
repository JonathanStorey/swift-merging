#if canImport(SwiftData)
import Foundation
import Merging
import SwiftData

/// Merges other contexts' saves into the main context's unsaved edits, property by property, by reading the
/// store's history.
///
/// For each object another author changed, it takes three snapshots of the merged properties: the base, as
/// last saved and kept in the ledger; ours, the main context's unsaved edits; and theirs, what's in the
/// store now. Their merge goes back into the main context's object, so the next save writes it. An object
/// the main context hasn't edited needs nothing, since the store already holds theirs.
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
    /// The main context's author, which marks its saves as ours in the history. Any other author's save,
    /// or one with no author, is theirs.
    public static let localAuthor = "Merging.local"

    public let container: ModelContainer
    public let ledger: any MergeLedger
    public let conflictPolicy: MergeConflictPolicy

    private let handlers: [any ModelMergeHandler]
    private var isMerging = false
    private nonisolated(unsafe) var observers: [any NSObjectProtocol] = []

    /// A coordinator for `types` in `container`. It sets the main context's author, and with a ledger that
    /// has no token yet it reads every object's base from the store.
    public init(container: ModelContainer, types: [any MergeableModel.Type], ledger: (any MergeLedger)? = nil,
                conflictPolicy: MergeConflictPolicy = .keepOurs) throws {
        self.container = container
        self.ledger = ledger ?? InMemoryMergeLedger()
        self.conflictPolicy = conflictPolicy
        handlers = types.map { makeHandler(for: $0) }
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

        let reader = ModelContext(container)
        var descriptor = HistoryDescriptor<DefaultHistoryTransaction>()
        if let token = ledger.token {
            descriptor.predicate = #Predicate { $0.token > token }
        }
        let transactions = try reader.fetchHistory(descriptor)
        guard !transactions.isEmpty else { return }

        let pass = MergePass(reader: reader, main: container.mainContext, ledger: ledger, conflictPolicy: conflictPolicy)
        for transaction in transactions {
            let isTheirs = transaction.author != Self.localAuthor
            for change in transaction.changes {
                for handler in handlers {
                    try handler.handle(change, isTheirs: isTheirs, in: pass)
                }
            }
            ledger.token = transaction.token
        }
        try ledger.save()
    }

    /// Merges on its own from now on: just before and just after the main context saves, so a save never
    /// writes over theirs and the next base is what it saved, and soon after any other context saves.
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

    /// Reads every object's base, and the token they're current to.
    private func seed() throws {
        let reader = ModelContext(container)
        ledger.token = try reader.fetchHistory(HistoryDescriptor<DefaultHistoryTransaction>()).last?.token
        for handler in handlers {
            try handler.seed(ledger, from: reader)
        }
        try ledger.save()
    }
}

@available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
extension ModelContainer {
    /// Merges `types` property by property from now on, and keeps the coordinator alive as long as the
    /// container. Call it once, after making the container.
    @discardableResult
    @MainActor
    public func enableMerging(_ types: any MergeableModel.Type..., ledger: (any MergeLedger)? = nil,
                              conflictPolicy: MergeConflictPolicy = .keepOurs) throws -> MergeCoordinator {
        let coordinator = try MergeCoordinator(container: self, types: types, ledger: ledger, conflictPolicy: conflictPolicy)
        coordinator.startObserving()
        activeCoordinators[ObjectIdentifier(self)] = coordinator
        return coordinator
    }
}

@MainActor private var activeCoordinators: [ObjectIdentifier: AnyObject] = [:]

/// What one pass over the history shares among the models it merges.
@available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
@MainActor
struct MergePass {
    /// A fresh context, so it reads what's in the store.
    let reader: ModelContext
    let main: ModelContext
    let ledger: any MergeLedger
    let conflictPolicy: MergeConflictPolicy
}

/// Merges one model type's changes.
@available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
@MainActor
protocol ModelMergeHandler {
    func seed(_ ledger: any MergeLedger, from reader: ModelContext) throws
    func handle(_ change: HistoryChange, isTheirs: Bool, in pass: MergePass) throws
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
            ledger.setBase(try JSONEncoder().encode(model.mergeSnapshot), for: model.persistentModelID)
        }
    }

    func handle(_ change: HistoryChange, isTheirs: Bool, in pass: MergePass) throws {
        let id = change.changedPersistentIdentifier
        switch change {
        case .insert(let insert):
            guard insert is DefaultHistoryInsert<Model>, let saved = try saved(id, in: pass) else { return }
            try setBase(saved.mergeSnapshot, for: id, in: pass)
        case .delete(let delete):
            guard delete is DefaultHistoryDelete<Model> else { return }
            pass.ledger.setBase(nil, for: id)
        case .update(let update):
            guard let update = update as? DefaultHistoryUpdate<Model>, touchesMergedProperty(update),
                  let saved = try saved(id, in: pass) else { return }
            let theirs = saved.mergeSnapshot
            if isTheirs, let base = try base(for: id, in: pass), let mine: Model = pass.main.registeredModel(for: id), mine.hasChanges {
                let ours = mine.mergeSnapshot
                // A clash on one property takes the policy's side there and leaves every other merge standing.
                let merged = switch pass.conflictPolicy {
                case .keepOurs: CodableTotalMerge<Snapshot, OursSide>().merge(base: base, ours: ours, theirs: theirs) ?? ours
                case .keepTheirs: CodableTotalMerge<Snapshot, TheirsSide>().merge(base: base, ours: ours, theirs: theirs) ?? theirs
                }
                if merged != ours { mine.applyMergeSnapshot(merged) }
            }
            // The store holds theirs until the main context saves the merge, which makes a pass of its own.
            try setBase(theirs, for: id, in: pass)
        @unknown default:
            return
        }
    }

    /// Whether an update changed a merged property. An update that names none is taken to change them all.
    private func touchesMergedProperty(_ update: DefaultHistoryUpdate<Model>) -> Bool {
        let merged = Set(Model.mergeKeyPaths)
        return update.updatedAttributes.isEmpty || update.updatedAttributes.contains { merged.contains($0) }
    }

    /// The object as saved, or `nil` if it's since been deleted.
    private func saved(_ id: PersistentIdentifier, in pass: MergePass) throws -> Model? {
        var descriptor = FetchDescriptor<Model>(predicate: #Predicate { $0.persistentModelID == id })
        descriptor.fetchLimit = 1
        return try pass.reader.fetch(descriptor).first
    }

    private func base(for id: PersistentIdentifier, in pass: MergePass) throws -> Snapshot? {
        guard let data = pass.ledger.base(for: id) else { return nil }
        return try JSONDecoder().decode(Snapshot.self, from: data)
    }

    private func setBase(_ snapshot: Snapshot, for id: PersistentIdentifier, in pass: MergePass) throws {
        pass.ledger.setBase(try JSONEncoder().encode(snapshot), for: id)
    }
}
#endif
