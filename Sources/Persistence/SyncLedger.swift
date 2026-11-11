#if canImport(SwiftData)
import CoreData
import Foundation
import SwiftData

/// Each object's sync state, kept by its Core Data URI and saved to `UserDefaults` so it survives a relaunch.
///
/// It learns everything from notifications every Core Data save posts, in this process:
///
/// - An app's own save of an object marks it pending.
/// - CloudKit's save of an object's metadata row with `needsUpload` cleared, after an export, marks it synced.
///   A row saved with `needsUpload` set marks it pending again.
/// - CloudKit's import of an object marks it synced, since it came from the server.
/// - A deletion forgets it.
/// - A CloudKit event or metadata row for a store marks that store as one that syncs.
final class SyncLedger: @unchecked Sendable {
    /// Posted, on any thread, after the ledger changes.
    static let didChange = Notification.Name("Persistence.SyncLedger.didChange")

    struct Entry: Codable, Equatable, Sendable {
        enum State: String, Codable, Sendable {
            case pending
            case synced
        }

        var state: State
        /// When pending, the oldest save not yet uploaded. When synced, when the server confirmed it.
        var date: Date
    }

    struct Contents: Codable, Equatable, Sendable {
        var entries: [String: Entry] = [:]
        var cloudStores: Set<String> = []
    }

    private let lock = NSLock()
    private var contents: Contents
    private let defaultsSuite: String?
    private let defaultsKey: String
    private let persistsChanges: Bool
    private var observers: [any NSObjectProtocol] = []

    /// A ledger saved under `defaultsKey` in the `UserDefaults` suite `defaultsSuite`, or the standard
    /// defaults, or not saved at all when `persists` is `false`.
    init(defaultsSuite: String? = nil, defaultsKey: String = "Persistence.SyncLedger", persists: Bool = true) {
        self.defaultsSuite = persists ? defaultsSuite : nil
        self.defaultsKey = defaultsKey
        if persists, let data = Self.defaults(defaultsSuite)?.data(forKey: defaultsKey),
           let saved = try? PropertyListDecoder().decode(Contents.self, from: data) {
            contents = saved
        } else {
            contents = Contents()
        }
        persistsChanges = persists
    }

    deinit {
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
    }

    // MARK: - Shared

    nonisolated(unsafe) private static var _shared: SyncLedger?
    private static let sharedLock = NSLock()

    /// The ledger every context and monitor reads, observing saves from the first time it's asked for.
    static var shared: SyncLedger { start(defaultsSuite: nil) }

    /// The shared ledger, made and started with `defaultsSuite` if it hasn't been yet.
    @discardableResult
    static func start(defaultsSuite: String?) -> SyncLedger {
        sharedLock.synchronized {
            if let _shared { return _shared }
            let ledger = SyncLedger(defaultsSuite: defaultsSuite)
            ledger.startObserving()
            _shared = ledger
            return ledger
        }
    }

    // MARK: - Reading

    /// An object's status, by its Core Data URI.
    func status(ofKey key: String) -> SyncStatus {
        guard let store = StoreRecords.store(ofKey: key) else { return .unsaved }
        return lock.synchronized {
            guard contents.cloudStores.contains(store) else { return .localOnly }
            switch contents.entries[key] {
            case nil: return .unknown
            case let entry? where entry.state == .pending: return .pending(since: entry.date)
            case let entry?: return .synced(at: entry.date)
            }
        }
    }

    /// Whether CloudKit has been seen syncing the store.
    func isCloudStore(_ store: String) -> Bool {
        lock.synchronized { contents.cloudStores.contains(store) }
    }

    /// How many objects are waiting to upload, in `stores`, or in every store when it's empty.
    func pendingCount(inStores stores: Set<String>) -> Int {
        lock.synchronized {
            contents.entries.filter { key, entry in
                guard entry.state == .pending, let store = StoreRecords.store(ofKey: key) else { return false }
                return contents.cloudStores.contains(store) && (stores.isEmpty || stores.contains(store))
            }.count
        }
    }

    var snapshot: Contents { lock.synchronized { contents } }

    // MARK: - Recording

    /// Records what one save, or one CloudKit event, said. Pending changes are applied before confirmations.
    func record(changed: [String] = [], confirmed: [String] = [], deleted: [String] = [], cloudStores: Set<String> = [],
                at date: Date = .now) {
        guard !changed.isEmpty || !confirmed.isEmpty || !deleted.isEmpty || !cloudStores.isEmpty else { return }
        let saved: Contents? = lock.synchronized {
            let before = contents
            for key in changed where contents.entries[key]?.state != .pending {
                contents.entries[key] = Entry(state: .pending, date: date)
            }
            for key in confirmed {
                contents.entries[key] = Entry(state: .synced, date: date)
            }
            for key in deleted {
                contents.entries[key] = nil
            }
            contents.cloudStores.formUnion(cloudStores)
            return contents == before ? nil : contents
        }
        guard let saved else { return }
        if persistsChanges, let data = try? PropertyListEncoder().encode(saved) {
            Self.defaults(defaultsSuite)?.set(data, forKey: defaultsKey)
        }
        NotificationCenter.default.post(name: Self.didChange, object: self)
    }

    // MARK: - Observing

    func startObserving() {
        let center = NotificationCenter.default
        let coreData = center.addObserver(forName: NSManagedObjectContext.didSaveObjectsNotification, object: nil, queue: nil) { [weak self] note in
            // Delivered on the saving context's queue, where its objects can be read.
            guard let context = note.object as? NSManagedObjectContext else { return }
            self?.contextDidSave(context, userInfo: note.userInfo ?? [:])
        }
        let swiftData = center.addObserver(forName: ModelContext.didSave, object: nil, queue: nil) { [weak self] note in
            let info = note.userInfo ?? [:]
            func keys(_ key: ModelContext.NotificationKey) -> [String] {
                ((info[key.rawValue] as? [PersistentIdentifier]) ?? []).compactMap(StoreRecords.key(of:))
            }
            self?.record(changed: keys(.insertedIdentifiers) + keys(.updatedIdentifiers), deleted: keys(.deletedIdentifiers))
        }
        let events = center.addObserver(forName: NSPersistentCloudKitContainer.eventChangedNotification, object: nil, queue: nil) { [weak self] note in
            guard let event = note.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey] as? NSPersistentCloudKitContainer.Event else { return }
            self?.record(cloudStores: [event.storeIdentifier])
        }
        lock.synchronized { observers = [coreData, swiftData, events] }
    }

    /// Reads one Core Data save: the app's own changes, CloudKit's imports, and CloudKit's metadata rows.
    func contextDidSave(_ context: NSManagedObjectContext, userInfo: [AnyHashable: Any]) {
        let author = context.transactionAuthor ?? ""
        let isImport = author == StoreRecords.importAuthor
        let isMirroring = author.hasPrefix(StoreRecords.mirroringAuthorPrefix)
        func objects(_ key: String) -> Set<NSManagedObject> { (userInfo[key] as? Set<NSManagedObject>) ?? [] }

        var changed: [String] = [], confirmed: [String] = [], deleted: [String] = []
        var stores: Set<String> = []
        for object in objects(NSInsertedObjectsKey).union(objects(NSUpdatedObjectsKey)) {
            let entity = object.entity.name ?? ""
            if entity == StoreRecords.metadataEntity {
                if let store = object.objectID.persistentStore?.identifier { stores.insert(store) }
                guard let row = StoreRecords.syncedObject(of: object) else { continue }
                if row.needsUpload { changed.append(row.key) } else { confirmed.append(row.key) }
            } else if entity.hasPrefix("NSCK") {
                continue
            } else if isImport {
                confirmed.append(StoreRecords.key(of: object))
            } else if !isMirroring {
                changed.append(StoreRecords.key(of: object))
            }
        }
        for object in objects(NSDeletedObjectsKey) where !(object.entity.name ?? "").hasPrefix("NSCK") {
            deleted.append(StoreRecords.key(of: object))
        }
        record(changed: changed, confirmed: confirmed, deleted: deleted, cloudStores: stores)
    }

    private static func defaults(_ suite: String?) -> UserDefaults? {
        guard let suite else { return .standard }
        return UserDefaults(suiteName: suite)
    }
}

/// Tracking every object's sync state, which `SyncMonitor.status(of:)` reads.
public enum SyncTracking {
    /// Starts tracking, saving what it learns in the `UserDefaults` suite named `defaultsSuite`, such as an
    /// App Group's, or the standard defaults. Call it once at launch, before the first save, so no change
    /// goes unseen. Getting a container's `sync` monitor starts it too, with the standard defaults.
    public static func start(defaultsSuite: String? = nil) {
        SyncLedger.start(defaultsSuite: defaultsSuite)
    }
}
#endif
