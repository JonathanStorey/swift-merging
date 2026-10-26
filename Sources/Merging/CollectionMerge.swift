// Sets and dictionaries encode in no particular order, and a dictionary whose keys aren't strings or
// integers encodes as a flat array of keys and values, so merging their encoded form element by element
// would mangle them. They bring rules of their own instead.

/// Three-way, an element is kept if either side added it, and removed if either side removed it. Two-way,
/// only equal sets merge.
extension Set: MergeRuled where Element: Codable {
    var mergeRule: MergeRule {
        MergeRule(Set.self) { ours, theirs, base in
            guard let base else {
                guard ours == theirs else { throw Unequal() }
                return ours
            }
            return ours.intersection(theirs).union(ours.subtracting(base)).union(theirs.subtracting(base))
        }
    }
}

/// Merges key by key, like an object, whatever the key's type.
extension Dictionary: MergeRuled where Key: Codable, Value: Codable {
    var mergeRule: MergeRule {
        MergeRule(Dictionary.self) { ours, theirs, base in
            var keys = KeyTable()
            let mine = try keys.object(ours), other = try keys.object(theirs)
            let merged: Snapshot = if let base {
                try Snapshot.object(mine).merging(.object(other), base: .object(keys.object(base)))
            } else {
                try Snapshot.object(mine).merging(.object(other))
            }
            guard case .object(let object) = merged else { throw Unequal() }
            let decoder = SnapshotDecoder()
            var result: Dictionary = [:]
            for (key, value) in object { result[keys.keys[key]!] = try decoder.decode(Value.self, from: value) }
            return result
        }
    }

    /// The dictionaries' keys by their canonical text, so equal keys line up across versions.
    private struct KeyTable {
        var keys: [String: Key] = [:]
        let encoder = SnapshotEncoder(isPart: true)

        mutating func object(_ dictionary: Dictionary) throws -> [String: Snapshot] {
            var object: [String: Snapshot] = [:]
            for (key, value) in dictionary {
                let text = try encoder.encode(key).canonical
                keys[text] = key
                object[text] = try encoder.encode(value)
            }
            return object
        }
    }
}

/// Thrown inside a rule, which reports it as a conflict of the whole set or dictionary.
private struct Unequal: Error {}

extension Snapshot {
    /// Text that's the same for equal snapshots and different for different ones, with object keys sorted.
    var canonical: String {
        switch self {
        case .null: "null"
        case .bool(let value): "\(value)"
        case .int(let value): "i\(value)"
        case .uint(let value): "u\(value)"
        case .double(let value): "d\(value)"
        case .string(let value): value.debugDescription
        case .array(let values): "[" + values.map(\.canonical).joined(separator: ",") + "]"
        case .object(let object):
            "{" + object.keys.sorted().map { $0.debugDescription + ":" + object[$0]!.canonical }.joined(separator: ",") + "}"
        case .merged(let data, _): data.canonical
        }
    }
}
