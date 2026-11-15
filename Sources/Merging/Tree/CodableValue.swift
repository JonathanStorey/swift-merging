/// A value's stored form, as JSON would hold it: what its `Codable` conformance encodes, without the
/// formatting. It's the element of a `CodableDifference`.
///
/// ```swift
/// let difference = try edited.codableDifference(from: original)
/// if case .replace(_, .int(let old), .int(let new))? = difference.first { print(old, new) }
/// ```
///
/// Dates are stored as seconds since 2001, enums with raw values as their raw value, and an optional
/// that's `nil` is left out of its object.
public enum CodableValue: Hashable, Sendable {
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
    case array([CodableValue])
    /// The properties of a struct or class, or the entries of a dictionary, by key.
    case object([String: CodableValue])
}

extension CodableValue {
    /// The tree of a value.
    init(encoding value: some Encodable) throws {
        self.init(try TreeEncoder().encode(value))
    }

    /// The value this tree holds, decoded as `type`.
    func decode<T: Decodable>(as type: T.Type = T.self) throws -> T {
        try TreeDecoder().decode(type, from: MergeTree(self))
    }

    var isNull: Bool { self == .null }

    var bool: Bool? {
        guard case .bool(let value) = self else { return nil }
        return value
    }

    /// The whole number, if it fits in an `Int64`.
    var int: Int64? {
        switch self {
        case .int(let value): value
        case .uint(let value): Int64(exactly: value)
        default: nil
        }
    }

    /// Any number, as a `Double`.
    var double: Double? {
        switch self {
        case .int(let value): Double(value)
        case .uint(let value): Double(value)
        case .double(let value): value
        default: nil
        }
    }

    var string: String? {
        guard case .string(let value) = self else { return nil }
        return value
    }

    var array: [CodableValue]? {
        guard case .array(let value) = self else { return nil }
        return value
    }

    var object: [String: CodableValue]? {
        guard case .object(let value) = self else { return nil }
        return value
    }

    /// The property or entry for `key`, if this is an object that has it. Setting it adds or replaces the
    /// entry, and setting `nil` removes it. Setting it on anything but an object does nothing.
    ///
    /// ```swift
    /// tree["address"]?["city"] = "Bergen"
    /// ```
    subscript(key: String) -> CodableValue? {
        get { object?[key] }
        set {
            guard case .object(var object) = self else { return }
            object[key] = newValue
            self = .object(object)
        }
    }

    /// The element at `index`, if this is an array that long. Setting it replaces the element, and setting
    /// `nil` removes it. Setting it outside the array does nothing.
    subscript(index: Int) -> CodableValue? {
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
    var children: [CodableValue] {
        switch self {
        case .array(let array): array
        case .object(let object): object.keys.sorted().map { object[$0]! }
        default: []
        }
    }
}

extension CodableValue: CustomStringConvertible {
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

extension CodableValue: Codable {
    /// Plain JSON. A whole `double` such as `2.0` may come back as `int`, which decodes the same.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .int(let value): try container.encode(value)
        case .uint(let value): try container.encode(value)
        case .double(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .array(let values): try container.encode(values)
        case .object(let object): try container.encode(object)
        }
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int64.self) {
            self = .int(value)
        } else if let value = try? container.decode(UInt64.self) {
            self = .uint(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let values = try? container.decode([CodableValue].self) {
            self = .array(values)
        } else {
            self = .object(try container.decode([String: CodableValue].self))
        }
    }
}

extension CodableValue: ExpressibleByNilLiteral, ExpressibleByBooleanLiteral, ExpressibleByIntegerLiteral, ExpressibleByFloatLiteral,
    ExpressibleByStringLiteral, ExpressibleByArrayLiteral, ExpressibleByDictionaryLiteral
{
    public init(nilLiteral: ()) { self = .null }
    public init(booleanLiteral value: Bool) { self = .bool(value) }
    public init(integerLiteral value: Int64) { self = .int(value) }
    public init(floatLiteral value: Double) { self = .double(value) }
    public init(stringLiteral value: String) { self = .string(value) }
    public init(arrayLiteral elements: CodableValue...) { self = .array(elements) }

    public init(dictionaryLiteral elements: (String, CodableValue)...) {
        self = .object(Dictionary(elements, uniquingKeysWith: { _, last in last }))
    }
}

extension CodableValue {
    /// The merge tree's data, without its merge kinds.
    init(_ tree: MergeTree) {
        self = switch tree {
        case .null: .null
        case .bool(let value): .bool(value)
        case .int(let value): .int(value)
        case .uint(let value): .uint(value)
        case .double(let value): .double(value)
        case .string(let value): .string(value)
        case .array(let values): .array(values.map(CodableValue.init))
        case .object(let object): .object(object.mapValues(CodableValue.init))
        case .merged(let data, _): CodableValue(data)
        }
    }
}

extension MergeTree {
    /// A merge tree of this tree's data, with no merge kinds.
    init(_ tree: CodableValue) {
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
