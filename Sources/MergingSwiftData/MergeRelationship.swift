#if canImport(SwiftData)
import Foundation
import SwiftData

/// How `@MergeableModel` snapshots and restores a relationship. A snapshot holds each related object as a
/// key, the object's Core Data URI (`x-coredata://…`), which is what the store reports when it saves, and
/// which stays the same however the identifier was made. A to-many relationship is a set of keys, since
/// SwiftData doesn't keep its order.
public enum MergeRelationship {
    /// A related object's key: its Core Data URI, or its identifier's encoded form if that holds no URI.
    public static func key(_ id: PersistentIdentifier) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        guard let data = try? encoder.encode(id) else { return "\(id)" }
        if let object = try? JSONSerialization.jsonObject(with: data), let uri = coreDataURI(in: object) {
            registry.remember(id, encoded: data, uri: uri)
            return uri
        }
        return String(decoding: data, as: UTF8.self)
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
        guard let context, let id = identifier(forKey: key) else { return nil }
        // A decoded identifier doesn't find a registered object, but a fetch by it does, and returns the
        // context's own instance.
        var descriptor = FetchDescriptor<Related>(predicate: #Predicate { $0.persistentModelID == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    /// The identifier for a key. One this process has made a key for comes back as it was. Any other is
    /// rebuilt from the encoded form of one it has, with the URI's store, entity, and primary key swapped in.
    static func identifier(forKey key: String, useKnown: Bool = true) -> PersistentIdentifier? {
        if useKnown, let id = registry.identifier(for: key) { return id }
        if key.hasPrefix("{") {
            return try? JSONDecoder().decode(PersistentIdentifier.self, from: Data(key.utf8))
        }
        guard let target = CoreDataURI(key), let template = registry.template(excluding: key),
              let source = CoreDataURI(template.uri),
              let object = try? JSONSerialization.jsonObject(with: template.encoded) else { return nil }
        let replacements = [source.text: target.text, source.store: target.store, source.entity: target.entity, source.primaryKey: target.primaryKey]
        let rebuilt = replacingStrings(in: object, with: replacements)
        guard JSONSerialization.isValidJSONObject(rebuilt), let data = try? JSONSerialization.data(withJSONObject: rebuilt) else { return nil }
        return try? JSONDecoder().decode(PersistentIdentifier.self, from: data)
    }

    private static let registry = IdentifierRegistry()

    private static func coreDataURI(in object: Any) -> String? {
        switch object {
        case let string as String: return string.hasPrefix("x-coredata://") ? string : nil
        case let dictionary as [String: Any]: return dictionary.keys.sorted().lazy.compactMap { coreDataURI(in: dictionary[$0]!) }.first
        case let array as [Any]: return array.lazy.compactMap { coreDataURI(in: $0) }.first
        default: return nil
        }
    }

    private static func replacingStrings(in object: Any, with replacements: [String: String]) -> Any {
        switch object {
        case let string as String: return replacements[string] ?? string
        case let dictionary as [String: Any]: return dictionary.mapValues { replacingStrings(in: $0, with: replacements) }
        case let array as [Any]: return array.map { replacingStrings(in: $0, with: replacements) }
        default: return object
        }
    }
}

/// A Core Data URI's parts: `x-coredata://<store>/<entity>/<primary key>`.
private struct CoreDataURI {
    let text: String
    let store: String
    let entity: String
    let primaryKey: String

    init?(_ text: String) {
        guard text.hasPrefix("x-coredata://") else { return nil }
        let parts = text.dropFirst("x-coredata://".count).split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 3, !parts[0].isEmpty else { return nil }
        self.text = text
        store = String(parts[0])
        entity = String(parts[1])
        primaryKey = String(parts[2])
    }
}

/// The identifiers this process has made keys for, so a key comes back as the identifier it came from.
private final class IdentifierRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var identifiers: [String: PersistentIdentifier] = [:]
    private var encoded: [String: Data] = [:]

    func remember(_ id: PersistentIdentifier, encoded data: Data, uri: String) {
        lock.synchronized {
            identifiers[uri] = id
            encoded[uri] = data
        }
    }

    func identifier(for key: String) -> PersistentIdentifier? {
        lock.synchronized { identifiers[key] }
    }

    func template(excluding key: String) -> (uri: String, encoded: Data)? {
        lock.synchronized { encoded.first { $0.key != key && !$0.key.hasPrefix("x-coredata:///") }.map { ($0.key, $0.value) } }
    }
}
#endif
