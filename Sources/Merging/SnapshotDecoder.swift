/// Decodes a value from a `MergeTree`.
struct SnapshotDecoder {
    func decode<T: Decodable>(_ type: T.Type, from snapshot: MergeTree) throws -> T {
        try Reader(snapshot, codingPath: []).read(type)
    }
}

/// The decoder for one value in a snapshot.
private struct Reader: Decoder {
    let snapshot: MergeTree
    let codingPath: [any CodingKey]
    var userInfo: [CodingUserInfoKey: Any] { [:] }

    init(_ snapshot: MergeTree, codingPath: [any CodingKey]) {
        var snapshot = snapshot
        while case .merged(let data, _) = snapshot { snapshot = data }
        self.snapshot = snapshot
        self.codingPath = codingPath
    }

    var isNull: Bool { snapshot == .null }

    func read(_ type: Bool.Type) throws -> Bool {
        guard case .bool(let value) = snapshot else { throw mismatch(type) }
        return value
    }

    func read(_ type: String.Type) throws -> String {
        guard case .string(let value) = snapshot else { throw mismatch(type) }
        return value
    }

    func read(_ type: Double.Type) throws -> Double {
        switch snapshot {
        case .double(let value): value
        case .int(let value): Double(value)
        case .uint(let value): Double(value)
        default: throw mismatch(type)
        }
    }

    func read(_ type: Float.Type) throws -> Float {
        Float(try read(Double.self))
    }

    func read<T: FixedWidthInteger & Decodable>(_ type: T.Type) throws -> T {
        let value: T? = switch snapshot {
        case .int(let value): T(exactly: value)
        case .uint(let value): T(exactly: value)
        case .double(let value): T(exactly: value)
        default: nil
        }
        guard let value else { throw mismatch(type) }
        return value
    }

    func read<T: Decodable>(_ type: T.Type) throws -> T {
        try T(from: self)
    }

    func mismatch(_ type: Any.Type) -> DecodingError {
        DecodingError.typeMismatch(type, DecodingError.Context(codingPath: codingPath, debugDescription: "Found \(snapshot)"))
    }

    func container<Key: CodingKey>(keyedBy type: Key.Type) throws -> KeyedDecodingContainer<Key> {
        guard case .object(let object) = snapshot else { throw mismatch([String: Any].self) }
        return KeyedDecodingContainer(KeyedContainer(object: object, codingPath: codingPath))
    }

    func unkeyedContainer() throws -> any UnkeyedDecodingContainer {
        guard case .array(let array) = snapshot else { throw mismatch([Any].self) }
        return UnkeyedContainer(array: array, codingPath: codingPath)
    }

    func singleValueContainer() -> any SingleValueDecodingContainer { self }
}

extension Reader: SingleValueDecodingContainer {
    func decodeNil() -> Bool { isNull }
    func decode(_ type: Bool.Type) throws -> Bool { try read(type) }
    func decode(_ type: String.Type) throws -> String { try read(type) }
    func decode(_ type: Double.Type) throws -> Double { try read(type) }
    func decode(_ type: Float.Type) throws -> Float { try read(type) }
    func decode(_ type: Int.Type) throws -> Int { try read(type) }
    func decode(_ type: Int8.Type) throws -> Int8 { try read(type) }
    func decode(_ type: Int16.Type) throws -> Int16 { try read(type) }
    func decode(_ type: Int32.Type) throws -> Int32 { try read(type) }
    func decode(_ type: Int64.Type) throws -> Int64 { try read(type) }
    func decode(_ type: UInt.Type) throws -> UInt { try read(type) }
    func decode(_ type: UInt8.Type) throws -> UInt8 { try read(type) }
    func decode(_ type: UInt16.Type) throws -> UInt16 { try read(type) }
    func decode(_ type: UInt32.Type) throws -> UInt32 { try read(type) }
    func decode(_ type: UInt64.Type) throws -> UInt64 { try read(type) }
    func decode<T: Decodable>(_ type: T.Type) throws -> T { try read(type) }
}

private struct KeyedContainer<Key: CodingKey>: KeyedDecodingContainerProtocol {
    let object: [String: MergeTree]
    let codingPath: [any CodingKey]

    var allKeys: [Key] { object.keys.compactMap(Key.init(stringValue:)) }

    func contains(_ key: Key) -> Bool { object[key.stringValue] != nil }

    func reader(forKey key: some CodingKey) throws -> Reader {
        guard let value = object[key.stringValue] else {
            throw DecodingError.keyNotFound(key, DecodingError.Context(codingPath: codingPath, debugDescription: "No value for \(key.stringValue)"))
        }
        return Reader(value, codingPath: codingPath + [key])
    }

    func decodeNil(forKey key: Key) throws -> Bool { try reader(forKey: key).isNull }
    func decode(_ type: Bool.Type, forKey key: Key) throws -> Bool { try reader(forKey: key).read(type) }
    func decode(_ type: String.Type, forKey key: Key) throws -> String { try reader(forKey: key).read(type) }
    func decode(_ type: Double.Type, forKey key: Key) throws -> Double { try reader(forKey: key).read(type) }
    func decode(_ type: Float.Type, forKey key: Key) throws -> Float { try reader(forKey: key).read(type) }
    func decode(_ type: Int.Type, forKey key: Key) throws -> Int { try reader(forKey: key).read(type) }
    func decode(_ type: Int8.Type, forKey key: Key) throws -> Int8 { try reader(forKey: key).read(type) }
    func decode(_ type: Int16.Type, forKey key: Key) throws -> Int16 { try reader(forKey: key).read(type) }
    func decode(_ type: Int32.Type, forKey key: Key) throws -> Int32 { try reader(forKey: key).read(type) }
    func decode(_ type: Int64.Type, forKey key: Key) throws -> Int64 { try reader(forKey: key).read(type) }
    func decode(_ type: UInt.Type, forKey key: Key) throws -> UInt { try reader(forKey: key).read(type) }
    func decode(_ type: UInt8.Type, forKey key: Key) throws -> UInt8 { try reader(forKey: key).read(type) }
    func decode(_ type: UInt16.Type, forKey key: Key) throws -> UInt16 { try reader(forKey: key).read(type) }
    func decode(_ type: UInt32.Type, forKey key: Key) throws -> UInt32 { try reader(forKey: key).read(type) }
    func decode(_ type: UInt64.Type, forKey key: Key) throws -> UInt64 { try reader(forKey: key).read(type) }
    func decode<T: Decodable>(_ type: T.Type, forKey key: Key) throws -> T { try reader(forKey: key).read(type) }

    func nestedContainer<NestedKey: CodingKey>(keyedBy type: NestedKey.Type, forKey key: Key) throws -> KeyedDecodingContainer<NestedKey> {
        try reader(forKey: key).container(keyedBy: type)
    }

    func nestedUnkeyedContainer(forKey key: Key) throws -> any UnkeyedDecodingContainer {
        try reader(forKey: key).unkeyedContainer()
    }

    func superDecoder() throws -> any Decoder { try reader(forKey: SnapshotKey.super) }
    func superDecoder(forKey key: Key) throws -> any Decoder { try reader(forKey: key) }
}

private struct UnkeyedContainer: UnkeyedDecodingContainer {
    let array: [MergeTree]
    let codingPath: [any CodingKey]
    var currentIndex = 0

    init(array: [MergeTree], codingPath: [any CodingKey]) {
        self.array = array
        self.codingPath = codingPath
    }

    var count: Int? { array.count }
    var isAtEnd: Bool { currentIndex >= array.count }

    /// The reader for the next element, moving past it.
    mutating func next(_ type: Any.Type) throws -> Reader {
        let key = SnapshotKey(intValue: currentIndex)
        guard !isAtEnd else {
            throw DecodingError.valueNotFound(type, DecodingError.Context(codingPath: codingPath + [key], debugDescription: "No more elements"))
        }
        currentIndex += 1
        return Reader(array[key.intValue!], codingPath: codingPath + [key])
    }

    mutating func decodeNil() throws -> Bool {
        guard !isAtEnd, Reader(array[currentIndex], codingPath: codingPath).isNull else { return false }
        currentIndex += 1
        return true
    }

    mutating func decode(_ type: Bool.Type) throws -> Bool { try next(type).read(type) }
    mutating func decode(_ type: String.Type) throws -> String { try next(type).read(type) }
    mutating func decode(_ type: Double.Type) throws -> Double { try next(type).read(type) }
    mutating func decode(_ type: Float.Type) throws -> Float { try next(type).read(type) }
    mutating func decode(_ type: Int.Type) throws -> Int { try next(type).read(type) }
    mutating func decode(_ type: Int8.Type) throws -> Int8 { try next(type).read(type) }
    mutating func decode(_ type: Int16.Type) throws -> Int16 { try next(type).read(type) }
    mutating func decode(_ type: Int32.Type) throws -> Int32 { try next(type).read(type) }
    mutating func decode(_ type: Int64.Type) throws -> Int64 { try next(type).read(type) }
    mutating func decode(_ type: UInt.Type) throws -> UInt { try next(type).read(type) }
    mutating func decode(_ type: UInt8.Type) throws -> UInt8 { try next(type).read(type) }
    mutating func decode(_ type: UInt16.Type) throws -> UInt16 { try next(type).read(type) }
    mutating func decode(_ type: UInt32.Type) throws -> UInt32 { try next(type).read(type) }
    mutating func decode(_ type: UInt64.Type) throws -> UInt64 { try next(type).read(type) }
    mutating func decode<T: Decodable>(_ type: T.Type) throws -> T { try next(type).read(type) }

    mutating func nestedContainer<NestedKey: CodingKey>(keyedBy type: NestedKey.Type) throws -> KeyedDecodingContainer<NestedKey> {
        try next([String: Any].self).container(keyedBy: type)
    }

    mutating func nestedUnkeyedContainer() throws -> any UnkeyedDecodingContainer {
        try next([Any].self).unkeyedContainer()
    }

    mutating func superDecoder() throws -> any Decoder { try next(Any.self) }
}
