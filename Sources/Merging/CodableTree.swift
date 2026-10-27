/// A value's stored form, as JSON would hold it: what its `Codable` conformance encodes, without the
/// formatting. Merging works on trees, and a strategy whose value is `CodableTree` merges any property
/// by its stored form.
///
/// ```swift
/// let tree = try CodableTree(encoding: Point(x: 1, y: 2))   // {"x": 1, "y": 2}
/// tree["x"]?.int                                            // 1
/// let point = try tree.decode(as: Point.self)
/// ```
///
/// Dates are stored as seconds since 2001, enums with raw values as their raw value, and an optional
/// that's `nil` is left out of its object.
public enum CodableTree: Hashable, Sendable {
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
    case array([CodableTree])
    /// The properties of a struct or class, or the entries of a dictionary, by key.
    case object([String: CodableTree])
}

extension CodableTree {
    /// The tree of a value.
    public init(encoding value: some Encodable) throws {
        self.init(try TreeEncoder().encode(value))
    }

    /// The value this tree holds, decoded as `type`.
    public func decode<T: Decodable>(as type: T.Type = T.self) throws -> T {
        try TreeDecoder().decode(type, from: MergeTree(self))
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

    public var array: [CodableTree]? {
        guard case .array(let value) = self else { return nil }
        return value
    }

    public var object: [String: CodableTree]? {
        guard case .object(let value) = self else { return nil }
        return value
    }

    /// The property or entry for `key`, if this is an object that has it. Setting it adds or replaces the
    /// entry, and setting `nil` removes it. Setting it on anything but an object does nothing.
    ///
    /// ```swift
    /// tree["address"]?["city"] = "Bergen"
    /// ```
    public subscript(key: String) -> CodableTree? {
        get { object?[key] }
        set {
            guard case .object(var object) = self else { return }
            object[key] = newValue
            self = .object(object)
        }
    }

    /// The element at `index`, if this is an array that long. Setting it replaces the element, and setting
    /// `nil` removes it. Setting it outside the array does nothing.
    public subscript(index: Int) -> CodableTree? {
        get {
            guard let array, array.indices.contains(index) else { return nil }
            return array[index]
        }
        set {
            guard case .array(var array) = self, array.indices.contains(index) else { return }
            if let newValue { array[index] = newValue } else { array.remove(at: index) }
            self = .array(array)
        }
    }

    /// The nodes directly inside this one: an array's elements, or an object's values in key order. A
    /// single value has none.
    public var children: [CodableTree] {
        switch self {
        case .array(let array): array
        case .object(let object): object.keys.sorted().map { object[$0]! }
        default: []
        }
    }
}

extension CodableTree: CustomStringConvertible {
    /// The tree as JSON, with keys sorted.
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

extension CodableTree: ExpressibleByNilLiteral, ExpressibleByBooleanLiteral, ExpressibleByIntegerLiteral, ExpressibleByFloatLiteral,
    ExpressibleByStringLiteral, ExpressibleByArrayLiteral, ExpressibleByDictionaryLiteral
{
    public init(nilLiteral: ()) { self = .null }
    public init(booleanLiteral value: Bool) { self = .bool(value) }
    public init(integerLiteral value: Int64) { self = .int(value) }
    public init(floatLiteral value: Double) { self = .double(value) }
    public init(stringLiteral value: String) { self = .string(value) }
    public init(arrayLiteral elements: CodableTree...) { self = .array(elements) }

    public init(dictionaryLiteral elements: (String, CodableTree)...) {
        self = .object(Dictionary(elements, uniquingKeysWith: { _, last in last }))
    }
}

/// CodableTrees merge by their shape: objects key by key, arrays element by element, and anything else by
/// keeping the side that changed.
extension CodableTree: Mergeable {
    public func merging(with theirs: CodableTree, from base: CodableTree) throws(MergeConflict<CodableTree>) -> CodableTree {
        do {
            return CodableTree(try MergeTree(self).merging(with: MergeTree(theirs), from: MergeTree(base)))
        } catch {
            throw MergeConflict(base: error.base.map(CodableTree.init), ours: CodableTree(error.ours), theirs: CodableTree(error.theirs))
        }
    }

    public func merging(with theirs: CodableTree) throws(MergeConflict<CodableTree>) -> CodableTree {
        do {
            return CodableTree(try MergeTree(self).merging(with: MergeTree(theirs)))
        } catch {
            throw MergeConflict(ours: CodableTree(error.ours), theirs: CodableTree(error.theirs))
        }
    }
}

extension CodableTree {
    /// The merge tree's data, without its rules.
    init(_ tree: MergeTree) {
        self = switch tree {
        case .null: .null
        case .bool(let value): .bool(value)
        case .int(let value): .int(value)
        case .uint(let value): .uint(value)
        case .double(let value): .double(value)
        case .string(let value): .string(value)
        case .array(let values): .array(values.map(CodableTree.init))
        case .object(let object): .object(object.mapValues(CodableTree.init))
        case .merged(let data, _): CodableTree(data)
        }
    }
}

extension MergeTree {
    /// A merge tree of this tree's data, with no rules.
    init(_ tree: CodableTree) {
        self = switch tree {
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
