#if canImport(SwiftData)
import CoreData
import Foundation

/// Records each object's values just before another author's save writes over them, which is the base a
/// merge needs and the one thing the store's history doesn't keep.
///
/// SwiftData saves through Core Data, and Core Data posts `willSaveObjectsNotification` from the saving
/// context before it writes. At that moment each updated object's `committedValues(forKeys:)` is the row as
/// stored and its `changedValues()` is what's about to replace it. This keeps both, keyed by the object's
/// URI, until a merge pass uses them.
///
/// It relies on SwiftData keeping Core Data underneath. If that changes it records nothing, and the merge
/// falls back to the ledger's bases.
final class StoreChangeCapture: @unchecked Sendable {
    /// One object's change in one save.
    struct Record {
        /// The order records were made in.
        let sequence: Int
        /// The object's Core Data URI, which is also its `MergeRelationship` key.
        let object: String
        let author: String?
        /// The stored values of the properties the save changed, before it.
        let base: [String: Any]
        /// The values the save wrote, read again once it finished so new objects have their final URIs.
        var new: [String: Any]
        /// Whether the save finished.
        var isComplete = false
        fileprivate let context: ObjectIdentifier
    }

    private let lock = NSLock()
    private let storeURL: URL?
    private let ignoredAuthors: Set<String>
    private var records: [Record] = []
    private var saving: [ObjectIdentifier: [Int: NSManagedObject]] = [:]
    private var nextSequence = 0
    private var observers: [any NSObjectProtocol] = []
    private var _storeIdentifiers: Set<String> = []
    private var _mergePolicy: String?

    /// A capture of saves to the store at `storeURL` by any author but `ignoredAuthors`.
    init(storeURL: URL?, ignoredAuthors: Set<String>) {
        self.storeURL = storeURL.map(Self.normalized)
        self.ignoredAuthors = ignoredAuthors
    }

    deinit {
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
    }

    /// Starts recording. A store with no file, such as one in memory, records nothing.
    func start() {
        guard storeURL != nil else { return }
        let center = NotificationCenter.default
        let willSave = center.addObserver(forName: NSManagedObjectContext.willSaveObjectsNotification, object: nil, queue: nil) { [weak self] note in
            guard let context = note.object as? NSManagedObjectContext else { return }
            self?.willSave(context)
        }
        let didSave = center.addObserver(forName: NSManagedObjectContext.didSaveObjectsNotification, object: nil, queue: nil) { [weak self] note in
            guard let context = note.object as? NSManagedObjectContext else { return }
            self?.didSave(context)
        }
        lock.synchronized { observers = [willSave, didSave] }
    }

    /// The identifiers of the stores it has seen saves to.
    var storeIdentifiers: Set<String> { lock.synchronized { _storeIdentifiers } }

    /// The saving context's merge policy, as last seen, for diagnostics.
    var mergePolicy: String? { lock.synchronized { _mergePolicy } }

    /// The sequences of the records whose saves have finished.
    func completedSequences() -> Set<Int> {
        lock.synchronized { Set(records.filter(\.isComplete).map(\.sequence)) }
    }

    /// An object's records, oldest first.
    func records(forObject object: String) -> [Record] {
        lock.synchronized { records.filter { $0.object == object } }
    }

    /// Drops an object's records up to and including `sequence`, or all of them.
    func discard(object: String, through sequence: Int = .max) {
        lock.synchronized { records.removeAll { $0.object == object && $0.sequence <= sequence } }
    }

    // MARK: - Saves

    private func willSave(_ context: NSManagedObjectContext) {
        guard let stores = matchingStores(of: context) else { return }
        let contextID = ObjectIdentifier(context)
        let author = context.transactionAuthor
        lock.synchronized {
            _storeIdentifiers.formUnion(stores)
            let policy = context.mergePolicy as? NSMergePolicy
            _mergePolicy = "\(context.mergePolicy) type=\(policy.map { "\($0.mergeType.rawValue)" } ?? "?")"
            // A save that failed never finished its records.
            records.removeAll { $0.context == contextID && !$0.isComplete }
            saving[contextID] = nil
        }
        if let author, ignoredAuthors.contains(author) { return }

        var made: [(Record, NSManagedObject)] = []
        for object in context.updatedObjects {
            let changed = object.changedValues()
            guard !changed.isEmpty else { continue }
            let keys = Array(changed.keys)
            let committed = object.committedValues(forKeys: keys)
            let base = Dictionary(uniqueKeysWithValues: keys.map { ($0, Self.plain(committed[$0] ?? NSNull())) })
            let new = changed.mapValues(Self.plain)
            let record = Record(sequence: 0, object: object.objectID.uriRepresentation().absoluteString, author: author,
                                base: base, new: new, context: contextID)
            made.append((record, object))
        }
        guard !made.isEmpty else { return }
        lock.synchronized {
            var objects: [Int: NSManagedObject] = [:]
            for (record, object) in made {
                let numbered = Record(sequence: nextSequence, object: record.object, author: record.author, base: record.base,
                                      new: record.new, context: contextID)
                records.append(numbered)
                objects[nextSequence] = object
                nextSequence += 1
            }
            saving[contextID] = objects
        }
    }

    private func didSave(_ context: NSManagedObjectContext) {
        let contextID = ObjectIdentifier(context)
        lock.synchronized {
            guard let objects = saving.removeValue(forKey: contextID) else { return }
            for index in records.indices where records[index].context == contextID && !records[index].isComplete {
                if let object = objects[records[index].sequence] {
                    var new: [String: Any] = [:]
                    for key in records[index].new.keys { new[key] = Self.plain(object.value(forKey: key) ?? NSNull()) }
                    records[index].new = new
                }
                records[index].isComplete = true
            }
        }
    }

    /// The identifiers of the context's stores that are ours, or `nil` if none is.
    private func matchingStores(of context: NSManagedObjectContext) -> [String]? {
        guard let storeURL, let coordinator = context.persistentStoreCoordinator else { return nil }
        let stores = coordinator.persistentStores.filter { $0.url.map(Self.normalized) == storeURL }
        return stores.isEmpty ? nil : stores.compactMap { $0.identifier }
    }

    private static func normalized(_ url: URL) -> URL {
        url.resolvingSymlinksInPath().standardizedFileURL
    }

    /// A Core Data value as plain Foundation values: a related object as its URI, a set or ordered set as an
    /// array, a date as seconds since the reference date, as `JSONEncoder` writes it.
    static func plain(_ value: Any) -> Any {
        switch value {
        case is NSNull: return NSNull()
        case let object as NSManagedObject: return object.objectID.uriRepresentation().absoluteString
        case let id as NSManagedObjectID: return id.uriRepresentation().absoluteString
        case let set as NSSet: return set.allObjects.map(plain)
        case let set as NSOrderedSet: return set.array.map(plain)
        case let date as Date: return date.timeIntervalSinceReferenceDate
        case let uuid as UUID: return uuid.uuidString
        case let url as URL: return url.absoluteString
        default: return value
        }
    }
}

/// Puts captured values into a snapshot by way of its JSON form, property by property.
enum SnapshotPatch {
    /// `snapshot` with each of `values` in place of the property of the same name. A value that won't
    /// convert to the property's type takes `fallback`'s value for it, or keeps the snapshot's.
    static func apply<Snapshot: Codable>(_ values: [String: Any], to snapshot: Snapshot, fallback: Snapshot?) -> Snapshot {
        guard !values.isEmpty, var object = jsonObject(snapshot) else { return snapshot }
        let fallbackObject = fallback.flatMap(jsonObject)
        for key in values.keys.sorted() {
            var converted = false
            for candidate in candidates(for: values[key]!) {
                var trial = object
                trial[key] = candidate
                if decode(Snapshot.self, from: trial) != nil {
                    object = trial
                    converted = true
                    break
                }
            }
            if !converted, let fallbackObject {
                var trial = object
                trial[key] = fallbackObject[key]
                if decode(Snapshot.self, from: trial) != nil { object = trial }
            }
        }
        return decode(Snapshot.self, from: object) ?? snapshot
    }

    /// Whether every one of `values` is already what `snapshot` holds.
    static func matches<Snapshot: Codable & Equatable>(_ values: [String: Any], _ snapshot: Snapshot) -> Bool {
        apply(values, to: snapshot, fallback: nil) == snapshot
    }

    private static func jsonObject<Snapshot: Codable>(_ snapshot: Snapshot) -> [String: Any]? {
        guard let data = try? JSONEncoder().encode(snapshot) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private static func decode<Snapshot: Codable>(_ type: Snapshot.Type, from object: [String: Any]) -> Snapshot? {
        guard JSONSerialization.isValidJSONObject(object), let data = try? JSONSerialization.data(withJSONObject: object) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    /// The JSON forms a stored value might take in a snapshot, likeliest first. `nil` leaves the property
    /// out, as an optional that's `nil` encodes.
    private static func candidates(for value: Any) -> [Any?] {
        switch value {
        case is NSNull:
            return [nil]
        case let data as Data:
            // Data itself, as JSONEncoder writes it, or a value SwiftData stored as data.
            var list: [Any?] = [data.base64EncodedString()]
            if let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) { list.append(jsonSafe(plist)) }
            if let json = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) { list.append(json) }
            let classes: [AnyClass] = [NSArray.self, NSDictionary.self, NSString.self, NSNumber.self, NSData.self, NSDate.self, NSNull.self]
            if let archived = try? NSKeyedUnarchiver.unarchivedObject(ofClasses: classes, from: data) { list.append(jsonSafe(archived)) }
            return list
        case let number as NSNumber:
            return [number, NSNumber(value: number.boolValue)]
        default:
            return [jsonSafe(value)]
        }
    }

    private static func jsonSafe(_ value: Any) -> Any {
        switch value {
        case let data as Data: return data.base64EncodedString()
        case let date as Date: return date.timeIntervalSinceReferenceDate
        case let uuid as UUID: return uuid.uuidString
        case let set as NSSet: return set.allObjects.map(jsonSafe)
        case let array as [Any]: return array.map(jsonSafe)
        case let dictionary as [String: Any]: return dictionary.mapValues(jsonSafe)
        default: return value
        }
    }
}
#endif

#if canImport(SwiftData)
extension NSLock {
    /// Runs `body` holding the lock.
    func synchronized<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
#endif
