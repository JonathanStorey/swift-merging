import Foundation

/// A decoder that answers every request with a placeholder and records what was asked: the keys, the
/// kind of each value, and which were decoded if present. One probe stands for one position in the schema.
final class SchemaProbe: Decoder {
    let codingPath: [any CodingKey]
    var userInfo: [CodingUserInfoKey: Any] { [:] }
    /// The types being decoded above this position, to stop a type that contains itself.
    private var types: [ObjectIdentifier]
    private var kind: CodableSchema?
    private var keyed: [String: SchemaProbe]?
    private var element: SchemaProbe?
    fileprivate var isOptional = false
    fileprivate var isDictionary = false
    private var isSet = false

    init(codingPath: [any CodingKey] = [], types: [ObjectIdentifier] = []) {
        self.codingPath = codingPath
        self.types = types
    }

    var schema: CodableSchema {
        let shape: CodableSchema = if let keyed {
            if isDictionary, let value = keyed[Self.dictionaryKey] { .dictionary(value.schema) } else { .object(keyed.mapValues(\.schema)) }
        } else if let element {
            isSet ? .set(element.schema) : .array(element.schema)
        } else {
            kind ?? .object([:])
        }
        return isOptional ? .optional(shape) : shape
    }

    /// Decodes a placeholder `T` at this position, recording its shape.
    func decode<T: Decodable>(_ type: T.Type) throws -> T {
        if let value = try placeholder(type) { return value }
        let id = ObjectIdentifier(type)
        guard !types.contains(id) else {
            throw DecodingError.dataCorrupted(.init(codingPath: codingPath, debugDescription: "\(type) contains itself, which a CodableSchema can't describe"))
        }
        types.append(id)
        defer { types.removeLast() }
        do {
            let value = try T(from: self)
            if (type as? any MergeKinded.Type)?.mergeKind == .set { isSet = true }
            return value
        } catch DecodingError.dataCorrupted(let context) where type is any RawRepresentable.Type {
            let reason = "\(type) rejected a placeholder raw value. Make it CaseIterable to read its schema."
            throw DecodingError.dataCorrupted(.init(codingPath: context.codingPath, debugDescription: reason, underlyingError: nil))
        }
    }

    /// A real instance for types whose decoding checks its input or that the schema names: a date, every
    /// case of a `CaseIterable` enum, and a `UUID` or `URL` with the shape its encoding has.
    private func placeholder<T>(_ type: T.Type) throws -> T? {
        if type is Date.Type {
            kind = .date
            return Date(timeIntervalSinceReferenceDate: 0) as? T
        }
        if let iterable = type as? any CaseIterable.Type {
            let cases = allCases(of: iterable)
            guard let first = cases.first as? T else { return nil }
            kind = .enumeration(try cases.compactMap { $0 as? any Encodable }.map { try CodableRepresentation(encoding: $0) })
            return first
        }
        let instance: Any? = if type is UUID.Type { UUID() } else if type is URL.Type { URL(fileURLWithPath: "/") } else { nil }
        guard let value = instance as? T, let encodable = instance as? any Encodable else { return nil }
        kind = CodableSchema(shapeOf: try CodableRepresentation(encoding: encodable))
        return value
    }

    fileprivate func record<T>(_ kind: CodableSchema, _ placeholder: T) -> T {
        self.kind = kind
        return placeholder
    }

    fileprivate func child(forKey key: some CodingKey) -> SchemaProbe {
        if let child = keyed?[key.stringValue] { return child }
        if keyed == nil { keyed = [:] }
        let child = SchemaProbe(codingPath: codingPath + [key], types: types)
        keyed?[key.stringValue] = child
        return child
    }

    fileprivate func elementProbe() -> SchemaProbe {
        if let element { return element }
        let element = SchemaProbe(codingPath: codingPath + [TreeKey(intValue: 0)], types: types)
        self.element = element
        return element
    }

    /// The one key a dictionary is offered, which suits both `String` and `Int` keys.
    fileprivate static let dictionaryKey = "0"

    func container<Key: CodingKey>(keyedBy type: Key.Type) -> KeyedDecodingContainer<Key> {
        if keyed == nil { keyed = [:] }
        return KeyedDecodingContainer(ProbeKeyedContainer(probe: self))
    }

    func unkeyedContainer() -> any UnkeyedDecodingContainer {
        _ = elementProbe()
        return ProbeUnkeyedContainer(probe: self)
    }

    func singleValueContainer() -> any SingleValueDecodingContainer { self }
}

private func allCases<C: CaseIterable>(of type: C.Type) -> [Any] {
    type.allCases.map { $0 as Any }
}

extension SchemaProbe: SingleValueDecodingContainer {
    func decodeNil() -> Bool {
        isOptional = true
        return false
    }

    func decode(_ type: Bool.Type) -> Bool { record(.bool, false) }
    func decode(_ type: String.Type) -> String { record(.string, "a") }
    func decode(_ type: Double.Type) -> Double { record(.double, 0) }
    func decode(_ type: Float.Type) -> Float { record(.double, 0) }
    func decode(_ type: Int.Type) -> Int { record(.integer, 0) }
    func decode(_ type: Int8.Type) -> Int8 { record(.integer, 0) }
    func decode(_ type: Int16.Type) -> Int16 { record(.integer, 0) }
    func decode(_ type: Int32.Type) -> Int32 { record(.integer, 0) }
    func decode(_ type: Int64.Type) -> Int64 { record(.integer, 0) }
    func decode(_ type: UInt.Type) -> UInt { record(.integer, 0) }
    func decode(_ type: UInt8.Type) -> UInt8 { record(.integer, 0) }
    func decode(_ type: UInt16.Type) -> UInt16 { record(.integer, 0) }
    func decode(_ type: UInt32.Type) -> UInt32 { record(.integer, 0) }
    func decode(_ type: UInt64.Type) -> UInt64 { record(.integer, 0) }
}

/// Has every key, none of them `nil`, and offers one key to code that lists them, as a dictionary does.
private struct ProbeKeyedContainer<Key: CodingKey>: KeyedDecodingContainerProtocol {
    let probe: SchemaProbe
    var codingPath: [any CodingKey] { probe.codingPath }

    var allKeys: [Key] {
        probe.isDictionary = true
        return Key(stringValue: SchemaProbe.dictionaryKey).map { [$0] } ?? []
    }

    func contains(_ key: Key) -> Bool { true }

    /// Asked before decoding a value if present, so it marks that value optional.
    func decodeNil(forKey key: Key) -> Bool {
        probe.child(forKey: key).isOptional = true
        return false
    }

    func decode(_ type: Bool.Type, forKey key: Key) -> Bool { probe.child(forKey: key).decode(type) }
    func decode(_ type: String.Type, forKey key: Key) -> String { probe.child(forKey: key).decode(type) }
    func decode(_ type: Double.Type, forKey key: Key) -> Double { probe.child(forKey: key).decode(type) }
    func decode(_ type: Float.Type, forKey key: Key) -> Float { probe.child(forKey: key).decode(type) }
    func decode(_ type: Int.Type, forKey key: Key) -> Int { probe.child(forKey: key).decode(type) }
    func decode(_ type: Int8.Type, forKey key: Key) -> Int8 { probe.child(forKey: key).decode(type) }
    func decode(_ type: Int16.Type, forKey key: Key) -> Int16 { probe.child(forKey: key).decode(type) }
    func decode(_ type: Int32.Type, forKey key: Key) -> Int32 { probe.child(forKey: key).decode(type) }
    func decode(_ type: Int64.Type, forKey key: Key) -> Int64 { probe.child(forKey: key).decode(type) }
    func decode(_ type: UInt.Type, forKey key: Key) -> UInt { probe.child(forKey: key).decode(type) }
    func decode(_ type: UInt8.Type, forKey key: Key) -> UInt8 { probe.child(forKey: key).decode(type) }
    func decode(_ type: UInt16.Type, forKey key: Key) -> UInt16 { probe.child(forKey: key).decode(type) }
    func decode(_ type: UInt32.Type, forKey key: Key) -> UInt32 { probe.child(forKey: key).decode(type) }
    func decode(_ type: UInt64.Type, forKey key: Key) -> UInt64 { probe.child(forKey: key).decode(type) }
    func decode<T: Decodable>(_ type: T.Type, forKey key: Key) throws -> T { try probe.child(forKey: key).decode(type) }

    func nestedContainer<NestedKey: CodingKey>(keyedBy type: NestedKey.Type, forKey key: Key) -> KeyedDecodingContainer<NestedKey> {
        probe.child(forKey: key).container(keyedBy: type)
    }

    func nestedUnkeyedContainer(forKey key: Key) -> any UnkeyedDecodingContainer {
        probe.child(forKey: key).unkeyedContainer()
    }

    func superDecoder() -> any Decoder { probe.child(forKey: TreeKey.super) }
    func superDecoder(forKey key: Key) -> any Decoder { probe.child(forKey: key) }
}

/// Holds one element, so collections decode their element type once. Every element decoded lands on
/// that one position, for code that reads a fixed number without checking `isAtEnd`.
private struct ProbeUnkeyedContainer: UnkeyedDecodingContainer {
    let probe: SchemaProbe
    var codingPath: [any CodingKey] { probe.codingPath }
    var count: Int? { 1 }
    var currentIndex = 0
    var isAtEnd: Bool { currentIndex > 0 }

    private mutating func next() -> SchemaProbe {
        currentIndex += 1
        return probe.elementProbe()
    }

    mutating func decodeNil() -> Bool {
        probe.elementProbe().isOptional = true
        return false
    }

    mutating func decode(_ type: Bool.Type) -> Bool { next().decode(type) }
    mutating func decode(_ type: String.Type) -> String { next().decode(type) }
    mutating func decode(_ type: Double.Type) -> Double { next().decode(type) }
    mutating func decode(_ type: Float.Type) -> Float { next().decode(type) }
    mutating func decode(_ type: Int.Type) -> Int { next().decode(type) }
    mutating func decode(_ type: Int8.Type) -> Int8 { next().decode(type) }
    mutating func decode(_ type: Int16.Type) -> Int16 { next().decode(type) }
    mutating func decode(_ type: Int32.Type) -> Int32 { next().decode(type) }
    mutating func decode(_ type: Int64.Type) -> Int64 { next().decode(type) }
    mutating func decode(_ type: UInt.Type) -> UInt { next().decode(type) }
    mutating func decode(_ type: UInt8.Type) -> UInt8 { next().decode(type) }
    mutating func decode(_ type: UInt16.Type) -> UInt16 { next().decode(type) }
    mutating func decode(_ type: UInt32.Type) -> UInt32 { next().decode(type) }
    mutating func decode(_ type: UInt64.Type) -> UInt64 { next().decode(type) }
    mutating func decode<T: Decodable>(_ type: T.Type) throws -> T { try next().decode(type) }

    mutating func nestedContainer<NestedKey: CodingKey>(keyedBy type: NestedKey.Type) -> KeyedDecodingContainer<NestedKey> {
        next().container(keyedBy: type)
    }

    mutating func nestedUnkeyedContainer() -> any UnkeyedDecodingContainer {
        next().unkeyedContainer()
    }

    mutating func superDecoder() -> any Decoder { next() }
}
