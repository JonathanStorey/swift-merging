#if canImport(SwiftData)
import CloudKit
import CoreData
import Foundation
import SwiftData

/// How the module names objects and stores, and reads what CloudKit writes about them.
///
/// Everything here is public API: Core Data's object URIs, a store file's metadata, a `PersistentIdentifier`'s
/// `Codable` form, and the rows CloudKit's mirroring saves through ordinary Core Data notifications. It reads
/// CloudKit's per-object rows by entity and key name, and calls nothing private.
enum StoreRecords {
    /// The entity CloudKit keeps one row of sync state in for each object it mirrors.
    static let metadataEntity = "NSCKRecordMetadata"
    /// The author of the saves CloudKit makes when it imports records.
    static let importAuthor = "NSCloudKitMirroringDelegate.import"
    /// The prefix of every author CloudKit's mirroring saves with.
    static let mirroringAuthorPrefix = "NSCloudKitMirroringDelegate"

    /// An object's Core Data URI, `x-coredata://<store>/<entity>/p<primary key>`, which keys its state.
    static func key(of object: NSManagedObject) -> String {
        object.objectID.uriRepresentation().absoluteString
    }

    /// A model's Core Data URI, read from its identifier's encoded form, or `nil` if it has none.
    static func key(of id: PersistentIdentifier) -> String? {
        guard let data = try? JSONEncoder().encode(id),
              let object = try? JSONSerialization.jsonObject(with: data) else { return nil }
        return coreDataURI(in: object)
    }

    /// The store an object's URI names, or `nil` for an object that hasn't been saved.
    static func store(ofKey key: String) -> String? {
        guard let host = URL(string: key)?.host, !host.isEmpty else { return nil }
        return host
    }

    /// The identifier of the store file at `url`, which CloudKit's events name it by.
    static func storeIdentifier(at url: URL) -> String? {
        let metadata = try? NSPersistentStoreCoordinator.metadataForPersistentStore(type: .sqlite, at: url)
        return metadata?[NSStoreUUIDKey] as? String
    }

    /// The object a CloudKit metadata row is for, and whether CloudKit still has to upload it. The row's
    /// record type, less CloudKit's `CD_` prefix, is the entity. A row whose record hasn't been made yet,
    /// before an object's first upload, can't be placed and gives `nil`.
    static func syncedObject(of row: NSManagedObject) -> (key: String, store: String, needsUpload: Bool)? {
        guard let store = row.objectID.persistentStore?.identifier,
              let primaryKey = (row.value(forKey: "entityPK") as? NSNumber)?.int64Value,
              let fields = row.value(forKey: "ckRecordSystemFields") as? Data,
              let record = decodeSystemFields(fields) else { return nil }
        var entity = record.recordType
        if entity.hasPrefix("CD_") { entity.removeFirst(3) }
        let needsUpload = (row.value(forKey: "needsUpload") as? NSNumber)?.boolValue ?? true
        return ("x-coredata://\(store)/\(entity)/p\(primaryKey)", store, needsUpload)
    }

    /// A record from the system fields `CKRecord.encodeSystemFields(with:)` wrote.
    static func decodeSystemFields(_ data: Data) -> CKRecord? {
        guard let coder = try? NSKeyedUnarchiver(forReadingFrom: data) else { return nil }
        coder.requiresSecureCoding = true
        defer { coder.finishDecoding() }
        return CKRecord(coder: coder)
    }

    private static func coreDataURI(in object: Any) -> String? {
        switch object {
        case let string as String: return string.hasPrefix("x-coredata:") ? string : nil
        case let dictionary as [String: Any]: return dictionary.keys.sorted().lazy.compactMap { coreDataURI(in: dictionary[$0]!) }.first
        case let array as [Any]: return array.lazy.compactMap { coreDataURI(in: $0) }.first
        default: return nil
        }
    }
}

extension NSLock {
    /// Runs `body` holding the lock.
    func synchronized<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
#endif
