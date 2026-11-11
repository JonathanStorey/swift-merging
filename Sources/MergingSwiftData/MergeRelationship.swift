#if canImport(SwiftData)
import Foundation
import SwiftData

/// How `@MergeableModel` snapshots and restores a relationship. A snapshot holds each related object as a
/// key, its identifier's encoded form, since a decoded `PersistentIdentifier` doesn't hash like the one it
/// was encoded from. A to-many relationship is a set of keys, since SwiftData doesn't keep its order.
public enum MergeRelationship {
    /// A related object's key.
    public static func key(_ id: PersistentIdentifier) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return (try? encoder.encode(id)).map { String(decoding: $0, as: UTF8.self) } ?? "\(id)"
    }

    /// A to-one relationship's key.
    public static func key<Related: PersistentModel>(_ model: Related?) -> String? {
        model.map { key($0.persistentModelID) }
    }

    /// A to-many relationship's keys.
    public static func keys<Related: PersistentModel>(_ models: [Related]?) -> Set<String> {
        Set((models ?? []).map { key($0.persistentModelID) })
    }

    /// The objects for `keys`, from those already related where it can, and otherwise from `context`. A key
    /// whose object has been deleted is left out.
    public static func models<Related: PersistentModel>(_ keys: Set<String>, current: [Related]?, in context: ModelContext?) -> [Related] {
        let known = Dictionary((current ?? []).map { (key($0.persistentModelID), $0) }, uniquingKeysWith: { first, _ in first })
        return keys.sorted().compactMap { known[$0] ?? model(forKey: $0, in: context) }
    }

    /// The object for a to-one relationship's key, or `nil` if it has none or its object has been deleted.
    public static func model<Related: PersistentModel>(_ key: String?, current: Related?, in context: ModelContext?) -> Related? {
        guard let key else { return nil }
        if let current, self.key(current.persistentModelID) == key { return current }
        return model(forKey: key, in: context)
    }

    private static func model<Related: PersistentModel>(forKey key: String, in context: ModelContext?) -> Related? {
        guard let context, let id = try? JSONDecoder().decode(PersistentIdentifier.self, from: Data(key.utf8)) else { return nil }
        if let registered: Related = context.registeredModel(for: id) { return registered }
        var descriptor = FetchDescriptor<Related>(predicate: #Predicate { $0.persistentModelID == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }
}
#endif
