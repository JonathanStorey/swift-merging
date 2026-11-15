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
public struct CodableDifference: RandomAccessCollection, Hashable, Sendable {
    public typealias ChangeElement = CodableValue

    /// One difference between the two versions.
    public enum Change: Hashable, Sendable {
        /// A property, entry or element only the newer version has.
        case insert(path: Path, element: ChangeElement)
        /// A property, entry or element only the older version has.
        case remove(path: Path, element: ChangeElement)
        /// A value that differs between the versions.
        case replace(path: Path, old: ChangeElement, new: ChangeElement)

        public var path: Path {
            switch self {
            case .insert(let path, _), .remove(let path, _), .replace(let path, _, _): path
            }
        }
    }

    let changes: [Change]

    init(_ changes: [Change]) {
        self.changes = changes
    }

    /// The changes from `old` to `new`.
    public init<Value: Encodable>(from old: Value, to new: Value) throws {
        self = try CodableValue(encoding: new).difference(from: CodableValue(encoding: old))
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
        CodableDifference(changes.map { change in
            switch change {
            case .insert(let path, let element): .remove(path: path, element: element)
            case .remove(let path, let element): .insert(path: path, element: element)
            case .replace(let path, let old, let new): .replace(path: path, old: new, new: old)
            }
        })
    }
}

extension Encodable where Self: Decodable {
    /// This value with `difference` applied. A change whose path isn't in this value is skipped, and the
    /// result must decode, or this throws the decoding error.
    ///
    /// ```swift
    /// let edited = try original.applying(CodableDifference(from: original, to: edited))
    /// ```
    public func applying(_ difference: CodableDifference) throws -> Self {
        var value = try CodableValue(encoding: self)
        value.apply(difference)
        return try value.decode()
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

extension CodableValue {
    /// What changed from `other` to this value, in the order `forEach` visits.
    func difference(from other: CodableValue) -> CodableDifference {
        var changes: [CodableDifference.Change] = []
        Self.collect(from: other, to: self, at: .root, into: &changes)
        return CodableDifference(changes)
    }

    private static func collect(
        from old: CodableValue, to new: CodableValue, at path: CodableDifference.Path, into changes: inout [CodableDifference.Change]
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
        _ old: CodableValue?, _ new: CodableValue?, at path: CodableDifference.Path, into changes: inout [CodableDifference.Change]
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
    private mutating func insert(_ element: CodableValue, at path: CodableDifference.Path) {
        guard case .index(let index)? = path.components.last else {
            self[path] = element
            return
        }
        let parent = CodableDifference.Path(Array(path.components.dropLast()))
        guard case .array(var array)? = self[parent], index <= array.count else { return }
        array.insert(element, at: index)
        self[parent] = .array(array)
    }
}
