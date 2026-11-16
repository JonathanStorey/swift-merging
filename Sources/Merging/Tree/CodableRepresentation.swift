import Foundation

/// A value's stored form: what its `Codable` conformance encodes, without the formatting. It's the
/// element of a `CodableDifference`, and `dictionary()` gives an object's fields.
///
/// ```swift
/// let difference = try CodableDifference(from: original, to: edited)
/// if case .replace(_, .integer(let old), .integer(let new))? = difference.first { print(old, new) }
/// ```
///
/// A `Date`, `Data`, `UUID`, `Decimal` or `URL` keeps its type, so a value round-trips exactly and a store
/// with types of its own, such as a database, can map each one. JSON has none of them, so `json` writes
/// each as `JSONEncoder` does by default, and reading JSON back gives the plain value, which still decodes
/// as the typed one. Enums with raw values are stored as their raw value, and an optional that's `nil` is
/// left out of its object.
public enum CodableRepresentation: Hashable, Sendable {
    case null
    case bool(Bool)
    /// A whole number, from any integer type up to 64 bits, signed or not.
    case integer(Int128)
    /// A number with a fractional part, from `Double` or `Float`, including NaN and the infinities.
    case double(Double)
    case string(String)
    /// A `Date`. JSON holds it as seconds since 2001.
    case date(Date)
    /// Bytes. JSON holds them as a base64 string.
    case data(Data)
    /// A `UUID`. JSON holds it as its `uuidString`.
    case uuid(UUID)
    /// A `Decimal`, exactly. JSON holds it as a number.
    case decimal(Decimal)
    /// A `URL`. JSON holds it as its `absoluteString`.
    case url(URL)
    /// The elements of an array or other unkeyed collection, in their encoded order.
    case array([CodableRepresentation])
    /// The members of a `Set`, which has no order. JSON holds it as an array.
    case set(Set<CodableRepresentation>)
    /// The properties of a struct or class, or the entries of a dictionary, by key.
    case object([String: CodableRepresentation])
}

extension CodableRepresentation {
    /// The representation of `value`: what its `Encodable` conformance encodes.
    ///
    /// ```swift
    /// let representation = try CodableRepresentation(encoding: person)
    /// ```
    public init(encoding value: some Encodable) throws {
        self.init(try TreeEncoder().encode(value))
    }

    /// The value this represents, decoded as `type`.
    ///
    /// ```swift
    /// let person = try representation.decode(as: Person.self)
    /// let person = try CodableRepresentation.object(fields).decode(as: Person.self)
    /// ```
    public func decode<T: Decodable>(as type: T.Type = T.self) throws -> T {
        try TreeDecoder().decode(type, from: MergeTree(self))
    }

    /// The top-level properties or entries, one level deep, if this represents an object. Each key is a
    /// property name, which also suits a `CKRecord` field name, and a nested value stays one value.
    ///
    /// ```swift
    /// let fields = try CodableRepresentation(encoding: person).dictionary()   // ["age": 30, "child": {...}, "name": "Ana"]
    /// ```
    public func dictionary() -> [String: CodableRepresentation]? {
        object
    }

    var isNull: Bool { self == .null }

    var bool: Bool? {
        guard case .bool(let value) = self else { return nil }
        return value
    }

    var integer: Int128? {
        guard case .integer(let value) = self else { return nil }
        return value
    }

    /// Any number, as a `Double`.
    var double: Double? {
        switch self {
        case .integer(let value): Double(value)
        case .double(let value): value
        default: nil
        }
    }

    var string: String? {
        guard case .string(let value) = self else { return nil }
        return value
    }

    var array: [CodableRepresentation]? {
        guard case .array(let value) = self else { return nil }
        return value
    }

    var object: [String: CodableRepresentation]? {
        guard case .object(let value) = self else { return nil }
        return value
    }

    var members: Set<CodableRepresentation>? {
        guard case .set(let value) = self else { return nil }
        return value
    }

    /// The property or entry for `key`, if this is an object that has it. Setting it adds or replaces the
    /// entry, and setting `nil` removes it. Setting it on anything but an object does nothing.
    ///
    /// ```swift
    /// tree["address"]?["city"] = "Bergen"
    /// ```
    subscript(key: String) -> CodableRepresentation? {
        get { object?[key] }
        set {
            guard case .object(var object) = self else { return }
            object[key] = newValue
            self = .object(object)
        }
    }

    /// The element at `index`, if this is an array that long. Setting it replaces the element, and setting
    /// `nil` removes it. Setting it outside the array does nothing.
    subscript(index: Int) -> CodableRepresentation? {
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
    var children: [CodableRepresentation] {
        switch self {
        case .array(let array): array
        case .set(let members): members.ordered
        case .object(let object): object.keys.sorted().map { object[$0]! }
        default: []
        }
    }
}

extension CodableRepresentation {
    /// Whether both hold the same value. A double or a date compares bit for bit, so every NaN equals
    /// every other and `-0.0` isn't `0.0`. A decimal NaN equals itself too, and a URL compares by its
    /// absolute form, as JSON holds it.
    public static func == (lhs: CodableRepresentation, rhs: CodableRepresentation) -> Bool {
        switch (lhs, rhs) {
        case (.null, .null): true
        case let (.bool(lhs), .bool(rhs)): lhs == rhs
        case let (.integer(lhs), .integer(rhs)): lhs == rhs
        case let (.double(lhs), .double(rhs)): lhs.identity == rhs.identity
        case let (.string(lhs), .string(rhs)): lhs == rhs
        case let (.date(lhs), .date(rhs)): lhs.timeIntervalSinceReferenceDate.identity == rhs.timeIntervalSinceReferenceDate.identity
        case let (.data(lhs), .data(rhs)): lhs == rhs
        case let (.uuid(lhs), .uuid(rhs)): lhs == rhs
        case let (.decimal(lhs), .decimal(rhs)): lhs == rhs || lhs.isNaN && rhs.isNaN
        case let (.url(lhs), .url(rhs)): lhs.absoluteURL == rhs.absoluteURL
        case let (.array(lhs), .array(rhs)): lhs == rhs
        case let (.set(lhs), .set(rhs)): lhs == rhs
        case let (.object(lhs), .object(rhs)): lhs == rhs
        default: false
        }
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(caseIndex)
        switch self {
        case .null: break
        case .bool(let value): hasher.combine(value)
        case .integer(let value): hasher.combine(value)
        case .double(let value): hasher.combine(value.identity)
        case .string(let value): hasher.combine(value)
        case .date(let value): hasher.combine(value.timeIntervalSinceReferenceDate.identity)
        case .data(let value): hasher.combine(value)
        case .uuid(let value): hasher.combine(value)
        case .decimal(let value): hasher.combine(value.isNaN ? Decimal.nan : value)
        case .url(let value): hasher.combine(value.absoluteURL)
        case .array(let value): hasher.combine(value)
        case .set(let value): hasher.combine(value)
        case .object(let value): hasher.combine(value)
        }
    }

    /// The case's place in the declaration, which tells apart values whose text is the same.
    var caseIndex: Int {
        switch self {
        case .null: 0
        case .bool: 1
        case .integer: 2
        case .double: 3
        case .string: 4
        case .date: 5
        case .data: 6
        case .uuid: 7
        case .decimal: 8
        case .url: 9
        case .array: 10
        case .set: 11
        case .object: 12
        }
    }
}

private extension Double {
    /// The bits that identify this value, with every NaN the same.
    var identity: UInt64 { isNaN ? Double.nan.bitPattern : bitPattern }
}

extension CodableRepresentation: CustomStringConvertible {
    /// The tree as JSON, with keys and set members sorted and a date in ISO 8601.
    public var description: String {
        switch self {
        case .null: "null"
        case .bool(let value): "\(value)"
        case .integer(let value): "\(value)"
        case .double(let value): "\(value)"
        case .string(let value): value.debugDescription
        case .date(let value): value.ISO8601Format().debugDescription
        case .data(let value): value.base64EncodedString().debugDescription
        case .uuid(let value): value.uuidString.debugDescription
        case .decimal(let value): "\(value)"
        case .url(let value): value.absoluteString.debugDescription
        case .array(let values): "[" + values.map(\.description).joined(separator: ", ") + "]"
        case .set(let members): "[" + members.ordered.map(\.description).joined(separator: ", ") + "]"
        case .object(let object):
            "{" + object.keys.sorted().map { "\($0.debugDescription): \(object[$0]!)" }.joined(separator: ", ") + "}"
        }
    }
}

extension CodableRepresentation: Codable {
    /// Plain JSON. A typed value encodes as itself, so `JSONEncoder` writes it by its strategies, and
    /// reading JSON gives the plain value back: a date's number, or a UUID's string. A whole `double` such
    /// as `2.0` may come back as `int`. Each decodes as the original type.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .integer(let value):
            if let value = Int64(exactly: value) {
                try container.encode(value)
            } else if let value = UInt64(exactly: value) {
                try container.encode(value)
            } else {
                let context = EncodingError.Context(codingPath: encoder.codingPath, debugDescription: "\(value) is outside Int64 and UInt64.")
                throw EncodingError.invalidValue(value, context)
            }
        case .double(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .date(let value): try container.encode(value)
        case .data(let value): try container.encode(value)
        case .uuid(let value): try container.encode(value)
        case .decimal(let value): try container.encode(value)
        case .url(let value): try container.encode(value)
        case .array(let values): try container.encode(values)
        case .set(let members): try container.encode(members.ordered)
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
            self = .integer(Int128(value))
        } else if let value = try? container.decode(UInt64.self) {
            self = .integer(Int128(value))
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let values = try? container.decode([CodableRepresentation].self) {
            self = .array(values)
        } else {
            self = .object(try container.decode([String: CodableRepresentation].self))
        }
    }
}

extension CodableRepresentation {
    /// Compact JSON, UTF-8 encoded, with keys and set members sorted so equal representations give equal data. Throws for
    /// a `double` that JSON can't hold, such as infinity.
    public var data: Data {
        get throws {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
            return try encoder.encode(self)
        }
    }

    /// Compact JSON with keys sorted, as in `{"age":30,"name":"Ana"}`.
    public var json: String {
        get throws { String(decoding: try data, as: UTF8.self) }
    }

    /// The representation JSON `data` holds.
    public init(data: Data) throws {
        self = try JSONDecoder().decode(CodableRepresentation.self, from: data)
    }

    /// The representation a JSON string holds.
    public init(json: String) throws {
        try self.init(data: Data(json.utf8))
    }
}

extension CodableRepresentation: ExpressibleByNilLiteral, ExpressibleByBooleanLiteral, ExpressibleByIntegerLiteral, ExpressibleByFloatLiteral,
    ExpressibleByStringLiteral, ExpressibleByArrayLiteral, ExpressibleByDictionaryLiteral
{
    public init(nilLiteral: ()) { self = .null }
    public init(booleanLiteral value: Bool) { self = .bool(value) }
    public init(integerLiteral value: Int128) { self = .integer(value) }
    public init(floatLiteral value: Double) { self = .double(value) }
    public init(stringLiteral value: String) { self = .string(value) }
    public init(arrayLiteral elements: CodableRepresentation...) { self = .array(elements) }

    public init(dictionaryLiteral elements: (String, CodableRepresentation)...) {
        self = .object(Dictionary(elements, uniquingKeysWith: { _, last in last }))
    }
}

extension CodableRepresentation {
    /// The merge tree's data, with a set as `.set` and no other merge kinds.
    init(_ tree: MergeTree) {
        self = switch tree {
        case .null: .null
        case .bool(let value): .bool(value)
        case .integer(let value): .integer(value)
        case .double(let value): .double(value)
        case .string(let value): .string(value)
        case .date(let value): .date(value)
        case .data(let value): .data(value)
        case .uuid(let value): .uuid(value)
        case .decimal(let value): .decimal(value)
        case .url(let value): .url(value)
        case .array(let values): .array(values.map(CodableRepresentation.init))
        case .object(let object): .object(object.mapValues(CodableRepresentation.init))
        case .merged(.array(let values), .set): .set(Set(values.map(CodableRepresentation.init)))
        case .merged(let data, _): CodableRepresentation(data)
        }
    }
}

extension MergeTree {
    /// A merge tree of this tree's data, with a set marked as one.
    init(_ tree: CodableRepresentation) {
        self = switch tree {
        case .null: .null
        case .bool(let value): .bool(value)
        case .integer(let value): .integer(value)
        case .double(let value): .double(value)
        case .string(let value): .string(value)
        case .date(let value): .date(value)
        case .data(let value): .data(value)
        case .uuid(let value): .uuid(value)
        case .decimal(let value): .decimal(value)
        case .url(let value): .url(value)
        case .array(let values): .array(values.map(MergeTree.init))
        case .set(let members): .merged(.array(members.map(MergeTree.init)), .set)
        case .object(let object): .object(object.mapValues(MergeTree.init))
        }
    }
}
