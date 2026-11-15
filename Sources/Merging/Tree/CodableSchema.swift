import Synchronization

/// The shape a `Decodable` type has when it's encoded: its properties, their kinds, and which are
/// optional. It's read from the type alone, so the same type always gives the same schema.
///
/// ```swift
/// let schema = try CodableSchema(Person.self)
/// print(schema)                               // {age: integer, child: {grandchildren: [string]}?, name: string}
/// schema["child.grandchildren[0]"]            // .string
/// let changes = try CodableDifference(from: oldSchema, to: schema)
/// ```
///
/// Schemas are cached by type. A raw-value enum must be `CaseIterable`, and a type that contains
/// itself, an enum with associated values, or an `init(from:)` that rejects placeholder values throws.
public indirect enum CodableSchema: Hashable, Sendable {
    case bool
    /// Any integer type, signed or not.
    case integer
    /// `Double`, `Float` or `Date`.
    case double
    case string
    case optional(CodableSchema)
    /// An array or set, with its elements' schema.
    case array(CodableSchema)
    /// A dictionary keyed by `String` or `Int`, with its values' schema.
    case dictionary(CodableSchema)
    /// A struct or class, by property.
    case object([String: CodableSchema])

    public typealias Path = CodableDifference.Path

    /// The schema of `type`, from what its `init(from:)` asks a decoder for.
    public init<T: Decodable>(_ type: T.Type) throws {
        let key = ObjectIdentifier(type)
        if let cached = Self.cached(key) {
            self = cached
            return
        }
        let probe = SchemaProbe()
        _ = try probe.decode(type)
        self = probe.schema
        Self.cache(self, for: key)
    }

    /// The schema at `path`. An index steps into an array's elements, a key into an object's property or
    /// a dictionary's values, and either looks through an optional.
    public subscript(path: Path) -> CodableSchema? {
        var schema = self
        for component in path.components {
            if case .optional(let wrapped) = schema { schema = wrapped }
            switch (component, schema) {
            case (.key(let key), .object(let object)):
                guard let property = object[key] else { return nil }
                schema = property
            case (.key, .dictionary(let element)), (.index, .array(let element)):
                schema = element
            default:
                return nil
            }
        }
        return schema
    }
}

extension CodableSchema: CustomStringConvertible {
    /// Swift-like: `string?`, `[integer]`, `[string: bool]`, and objects as `{name: string}` with keys sorted.
    public var description: String {
        switch self {
        case .bool: "bool"
        case .integer: "integer"
        case .double: "double"
        case .string: "string"
        case .optional(let wrapped): "\(wrapped)?"
        case .array(let element): "[\(element)]"
        case .dictionary(let element): "[string: \(element)]"
        case .object(let object): "{" + object.keys.sorted().map { "\($0): \(object[$0]!)" }.joined(separator: ", ") + "}"
        }
    }
}

extension CodableSchema: Codable {
    /// Kinds are strings, as in `"string"`, and the rest are tagged: `{"optional": "string"}`,
    /// `{"array": "integer"}`, `{"dictionary": "bool"}`, `{"object": {"name": "string"}}`.
    public func encode(to encoder: any Encoder) throws {
        switch self {
        case .bool, .integer, .double, .string:
            var container = encoder.singleValueContainer()
            try container.encode(description)
        case .optional(let schema), .array(let schema), .dictionary(let schema):
            var container = encoder.container(keyedBy: Tag.self)
            try container.encode(schema, forKey: tag)
        case .object(let object):
            var container = encoder.container(keyedBy: Tag.self)
            try container.encode(object, forKey: .object)
        }
    }

    public init(from decoder: any Decoder) throws {
        if let kind = try? decoder.singleValueContainer().decode(String.self) {
            switch kind {
            case "bool": self = .bool
            case "integer": self = .integer
            case "double": self = .double
            case "string": self = .string
            default: throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unknown kind \(kind)"))
            }
            return
        }
        let container = try decoder.container(keyedBy: Tag.self)
        guard container.allKeys.count == 1, let tag = container.allKeys.first else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Expected one of optional, array, dictionary or object"))
        }
        switch tag {
        case .optional: self = .optional(try container.decode(CodableSchema.self, forKey: tag))
        case .array: self = .array(try container.decode(CodableSchema.self, forKey: tag))
        case .dictionary: self = .dictionary(try container.decode(CodableSchema.self, forKey: tag))
        case .object: self = .object(try container.decode([String: CodableSchema].self, forKey: tag))
        }
    }

    private enum Tag: String, CodingKey {
        case optional, array, dictionary, object
    }

    private var tag: Tag {
        switch self {
        case .optional: .optional
        case .array: .array
        case .dictionary: .dictionary
        default: .object
        }
    }
}

extension CodableSchema {
    /// The shape of one encoded value, for types the probe makes from a real instance.
    init(shapeOf value: CodableValue) {
        self = switch value {
        case .null: .optional(.object([:]))
        case .bool: .bool
        case .int, .uint: .integer
        case .double: .double
        case .string: .string
        case .array(let elements): .array(elements.first.map(CodableSchema.init(shapeOf:)) ?? .object([:]))
        case .object(let object): .object(object.mapValues(CodableSchema.init(shapeOf:)))
        }
    }
}

/// Schemas already read, by type.
private extension CodableSchema {
    static let schemas = Mutex<[ObjectIdentifier: CodableSchema]>([:])

    static func cached(_ key: ObjectIdentifier) -> CodableSchema? {
        schemas.withLock { $0[key] }
    }

    static func cache(_ schema: CodableSchema, for key: ObjectIdentifier) {
        schemas.withLock { $0[key] = schema }
    }
}
