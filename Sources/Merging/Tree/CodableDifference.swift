import Foundation

/// What changed between two versions of a `Codable` value, shaped like `CollectionDifference`: a collection
/// of changes, each at the deepest path where the versions differ, in path order.
///
/// ```swift
/// let difference = try CodableDifference(from: original, to: edited)
/// for change in difference { print(change) }      // ~ child.grandchildren[2]: "Ava" → "Eva"
/// let rebuilt = try original.applying(difference) // == edited
/// ```
///
/// Objects compare key by key and arrays index by index, so an element inserted mid-array shows as
/// replacements of the ones after it and an insertion at the end.
///
/// A `nil` optional property isn't encoded, so setting one is an insertion and clearing it a removal. An
/// optional inside an array keeps its place as `null`, so there it's a replacement from or to `.null`.
/// `CodableSchema` tells these apart: `schema[change.path]` is `.optional` for an optional.
public struct CodableDifference: RandomAccessCollection, Hashable, Sendable {
    public typealias ChangeElement = CodableRepresentation

    /// One difference between the two versions.
    public enum Change: Hashable, Sendable {
        /// A property, entry or element only the newer version has.
        case insert(path: CodablePath, element: ChangeElement)
        /// A property, entry or element only the older version has.
        case remove(path: CodablePath, element: ChangeElement)
        /// A value that differs between the versions.
        case replace(path: CodablePath, old: ChangeElement, new: ChangeElement)

        public var path: CodablePath {
            switch self {
            case .insert(let path, _), .remove(let path, _), .replace(let path, _, _): path
            }
        }
    }

    let changes: [Change]

    /// The `CodableSchema` id of the type the difference was made from, or `nil` if its schema can't
    /// be read. `applying(_:)` refuses a difference made for another schema.
    public let schemaID: UUID?

    init(_ changes: [Change], schemaID: UUID? = nil) {
        self.changes = changes
        self.schemaID = schemaID
    }

    /// The changes from `old` to `new`.
    public init<Value: Codable>(from old: Value, to new: Value) throws {
        let changes = try CodableRepresentation(encoding: new).difference(from: CodableRepresentation(encoding: old)).changes
        self.init(changes, schemaID: try? CodableSchema(Value.self).id)
    }

    public var startIndex: Int { changes.startIndex }
    public var endIndex: Int { changes.endIndex }
    public subscript(position: Int) -> Change { changes[position] }

    public var insertions: [Change] { changes.filter(\.isInsertion) }
    public var removals: [Change] { changes.filter(\.isRemoval) }
    public var replacements: [Change] { changes.filter(\.isReplacement) }

    /// The difference that undoes this one: insertions become removals, removals insertions, and each
    /// replacement swaps its old and new values.
    public func inverse() -> CodableDifference {
        let changes = changes.map { change -> Change in
            switch change {
            case .insert(let path, let element): .remove(path: path, element: element)
            case .remove(let path, let element): .insert(path: path, element: element)
            case .replace(let path, let old, let new): .replace(path: path, old: new, new: old)
            }
        }
        return CodableDifference(changes, schemaID: schemaID)
    }
}

extension Encodable where Self: Decodable {
    /// This value with `difference` applied. A change whose path isn't in this value is skipped, and the
    /// result must decode, or this throws the decoding error. A difference made for another schema
    /// throws before anything is applied.
    ///
    /// ```swift
    /// let edited = try original.applying(CodableDifference(from: original, to: edited))
    /// ```
    public func applying(_ difference: CodableDifference) throws -> Self {
        if let expected = difference.schemaID, let actual = try? CodableSchema(Self.self).id, expected != actual {
            let reason = "The difference was made for schema \(expected), but \(Self.self) has schema \(actual)."
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: reason))
        }
        var value = try CodableRepresentation(encoding: self)
        value.apply(difference)
        return try value.decode()
    }
}

/// A change as a single-key object naming its case: `{"replace": {"path": ["age"], "old": 30, "new": 31}}`.
extension CodableDifference.Change: Codable {}

extension CodableDifference: Codable {
    /// `{"schemaID": "…", "changes": [...]}`, leaving out a `nil` schema id.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(schemaID, forKey: .schemaID)
        try container.encode(changes, forKey: .changes)
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(try container.decode([Change].self, forKey: .changes), schemaID: try container.decodeIfPresent(UUID.self, forKey: .schemaID))
    }

    private enum CodingKeys: String, CodingKey {
        case schemaID, changes
    }
}

extension CodableDifference.Change: CustomStringConvertible {
    /// `+` for an insertion, `-` for a removal and `~` for a replacement, then the path and the values.
    public var description: String {
        switch self {
        case .insert(let path, let element): "+ \(path): \(element)"
        case .remove(let path, let element): "- \(path): \(element)"
        case .replace(let path, let old, let new): "~ \(path): \(old) → \(new)"
        }
    }
}

private extension CodableDifference.Change {
    var isInsertion: Bool {
        guard case .insert = self else { return false }
        return true
    }

    var isRemoval: Bool {
        guard case .remove = self else { return false }
        return true
    }

    var isReplacement: Bool {
        guard case .replace = self else { return false }
        return true
    }
}

extension CodableRepresentation {
    /// What changed from `other` to this value, in the order `forEach` visits.
    func difference(from other: CodableRepresentation) -> CodableDifference {
        var changes: [CodableDifference.Change] = []
        Self.collect(from: other, to: self, at: CodablePath(), into: &changes)
        return CodableDifference(changes)
    }

    private static func collect(
        from old: CodableRepresentation, to new: CodableRepresentation, at path: CodablePath, into changes: inout [CodableDifference.Change]
    ) {
        guard old != new else { return }
        switch (old, new) {
        case (.object(let before), .object(let after)):
            for key in Set(before.keys).union(after.keys).sorted() {
                compare(before[key], after[key], at: path.appending(.key(key)), into: &changes)
            }
        case (.array(let before), .array(let after)):
            for index in 0..<max(before.count, after.count) {
                // Not `? element : nil`, which would build `.null` from the literal.
                let old = before.indices.contains(index) ? Optional(before[index]) : .none
                let new = after.indices.contains(index) ? Optional(after[index]) : .none
                compare(old, new, at: path.appending(.index(index)), into: &changes)
            }
        default:
            changes.append(.replace(path: path, old: old, new: new))
        }
    }

    private static func compare(
        _ old: CodableRepresentation?, _ new: CodableRepresentation?, at path: CodablePath, into changes: inout [CodableDifference.Change]
    ) {
        switch (old, new) {
        case let (old?, new?): collect(from: old, to: new, at: path, into: &changes)
        case let (old?, nil): changes.append(.remove(path: path, element: old))
        case let (nil, new?): changes.append(.insert(path: path, element: new))
        case (nil, nil): break
        }
    }

    /// Applies `difference` like `RangeReplaceableCollection.applying(_:)`: replacements first, then
    /// removals from the last, so each index still points where it did, then insertions from the first.
    mutating func apply(_ difference: CodableDifference) {
        for case .replace(let path, _, let new) in difference {
            self[path] = new
        }
        for change in difference.removals.reversed() {
            self[change.path] = nil
        }
        for case .insert(let path, let element) in difference {
            insert(element, at: path)
        }
    }

    /// Puts `element` at `path`: into an array at its index, shifting what follows, or as an object's entry.
    private mutating func insert(_ element: CodableRepresentation, at path: CodablePath) {
        guard case .index(let index)? = path.last else {
            self[path] = element
            return
        }
        let parent = CodablePath(path.dropLast())
        guard case .array(var array)? = self[parent], index <= array.count else { return }
        array.insert(element, at: index)
        self[parent] = .array(array)
    }
}
