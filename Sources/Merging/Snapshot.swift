/// A value's stored form, as JSON would hold it: what its `Codable` conformance encodes, without the
/// formatting. Merging works on snapshots, and a strategy whose value is `Snapshot` merges any property
/// by its stored form.
///
/// ```swift
/// let snapshot = try Snapshot(encoding: Point(x: 1, y: 2))   // {"x": 1, "y": 2}
/// snapshot["x"]?.int                                         // 1
/// let point = try snapshot.decode(as: Point.self)
/// ```
///
/// Dates are stored as seconds since 2001, enums with raw values as their raw value, and an optional
/// that's `nil` is left out of its object.
public enum Snapshot: Hashable, Sendable {
    case null
    case bool(Bool)
    /// A whole number, from any integer type.
    case int(Int64)
    /// A whole number too large for `int`.
    case uint(UInt64)
    /// A number with a fractional part, from `Double` or `Float`.
    case double(Double)
    case string(String)
    /// The elements of an array or other unkeyed collection, such as a set, in their encoded order.
    case array([Snapshot])
    /// The properties of a struct or class, or the entries of a dictionary, by key.
    case object([String: Snapshot])
}

extension Snapshot {
    /// The snapshot of a value.
    public init(encoding value: some Encodable) throws {
        self.init(try SnapshotEncoder().encode(value))
    }

    /// The value this snapshot holds, decoded as `type`.
    public func decode<T: Decodable>(as type: T.Type = T.self) throws -> T {
        try SnapshotDecoder().decode(type, from: MergeTree(self))
    }

    public var isNull: Bool { self == .null }

    public var bool: Bool? {
        guard case .bool(let value) = self else { return nil }
        return value
    }

    /// The whole number, if it fits in an `Int64`.
    public var int: Int64? {
        switch self {
        case .int(let value): value
        case .uint(let value): Int64(exactly: value)
        default: nil
        }
    }

    /// Any number, as a `Double`.
    public var double: Double? {
        switch self {
        case .int(let value): Double(value)
        case .uint(let value): Double(value)
        case .double(let value): value
        default: nil
        }
    }

    public var string: String? {
        guard case .string(let value) = self else { return nil }
        return value
    }

    public var array: [Snapshot]? {
        guard case .array(let value) = self else { return nil }
        return value
    }

    public var object: [String: Snapshot]? {
        guard case .object(let value) = self else { return nil }
        return value
    }

    /// The property or entry for `key`, if this is an object that has it.
    public subscript(key: String) -> Snapshot? {
        object?[key]
    }

    /// The element at `index`, if this is an array that long.
    public subscript(index: Int) -> Snapshot? {
        guard let array, array.indices.contains(index) else { return nil }
        return array[index]
    }
}

extension Snapshot: CustomStringConvertible {
    /// The snapshot as JSON, with keys sorted.
    public var description: String {
        switch self {
        case .null: "null"
        case .bool(let value): "\(value)"
        case .int(let value): "\(value)"
        case .uint(let value): "\(value)"
        case .double(let value): "\(value)"
        case .string(let value): value.debugDescription
        case .array(let values): "[" + values.map(\.description).joined(separator: ", ") + "]"
        case .object(let object):
            "{" + object.keys.sorted().map { "\($0.debugDescription): \(object[$0]!)" }.joined(separator: ", ") + "}"
        }
    }
}

extension Snapshot: ExpressibleByNilLiteral, ExpressibleByBooleanLiteral, ExpressibleByIntegerLiteral, ExpressibleByFloatLiteral,
    ExpressibleByStringLiteral, ExpressibleByArrayLiteral, ExpressibleByDictionaryLiteral
{
    public init(nilLiteral: ()) { self = .null }
    public init(booleanLiteral value: Bool) { self = .bool(value) }
    public init(integerLiteral value: Int64) { self = .int(value) }
    public init(floatLiteral value: Double) { self = .double(value) }
    public init(stringLiteral value: String) { self = .string(value) }
    public init(arrayLiteral elements: Snapshot...) { self = .array(elements) }

    public init(dictionaryLiteral elements: (String, Snapshot)...) {
        self = .object(Dictionary(elements, uniquingKeysWith: { _, last in last }))
    }
}

/// Snapshots merge by their shape: objects key by key, arrays element by element, and anything else by
/// keeping the side that changed.
extension Snapshot: Mergeable {
    public func merging(_ theirs: Snapshot, base: Snapshot) throws(MergeConflict<Snapshot>) -> Snapshot {
        do {
            return Snapshot(try MergeTree(self).merging(MergeTree(theirs), base: MergeTree(base)))
        } catch {
            throw MergeConflict(base: error.base.map(Snapshot.init), ours: Snapshot(error.ours), theirs: Snapshot(error.theirs))
        }
    }

    public func merging(_ theirs: Snapshot) throws(MergeConflict<Snapshot>) -> Snapshot {
        do {
            return Snapshot(try MergeTree(self).merging(MergeTree(theirs)))
        } catch {
            throw MergeConflict(ours: Snapshot(error.ours), theirs: Snapshot(error.theirs))
        }
    }
}

extension Snapshot {
    /// The tree's data, without its rules.
    init(_ tree: MergeTree) {
        self = switch tree {
        case .null: .null
        case .bool(let value): .bool(value)
        case .int(let value): .int(value)
        case .uint(let value): .uint(value)
        case .double(let value): .double(value)
        case .string(let value): .string(value)
        case .array(let values): .array(values.map(Snapshot.init))
        case .object(let object): .object(object.mapValues(Snapshot.init))
        case .merged(let data, _): Snapshot(data)
        }
    }
}

extension MergeTree {
    /// A tree of the snapshot's data, with no rules.
    init(_ snapshot: Snapshot) {
        self = switch snapshot {
        case .null: .null
        case .bool(let value): .bool(value)
        case .int(let value): .int(value)
        case .uint(let value): .uint(value)
        case .double(let value): .double(value)
        case .string(let value): .string(value)
        case .array(let values): .array(values.map(MergeTree.init))
        case .object(let object): .object(object.mapValues(MergeTree.init))
        }
    }
}
