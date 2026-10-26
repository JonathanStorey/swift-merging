/// Encodes a value as a `Snapshot`.
struct SnapshotEncoder {
    func encode<T: Encodable>(_ value: T) throws -> Snapshot {
        let node = Node(codingPath: [])
        try node.store(value)
        return node.snapshot
    }
}

/// The encoder for one value in the snapshot being built. Containers add child nodes for their keys or
/// elements, so nested values can be written in any order.
private final class Node: Encoder {
    let codingPath: [any CodingKey]
    var userInfo: [CodingUserInfoKey: Any] { [:] }
    private var value: Snapshot?
    private var keyed: [String: Node]?
    private var unkeyed: [Node]?

    init(codingPath: [any CodingKey]) {
        self.codingPath = codingPath
    }

    var snapshot: Snapshot {
        if let keyed { return .object(keyed.mapValues(\.snapshot)) }
        if let unkeyed { return .array(unkeyed.map(\.snapshot)) }
        return value ?? .null
    }

    func store(_ value: Snapshot) { self.value = value }
    func store(_ value: Bool) { self.value = .bool(value) }
    func store(_ value: String) { self.value = .string(value) }
    func store(_ value: Double) { self.value = .double(value) }
    func store(_ value: Float) { self.value = .double(Double(value)) }
    func store<T: FixedWidthInteger & Encodable>(_ value: T) { self.value = Snapshot(value) }
    func store<T: Encodable>(_ value: T) throws { try value.encode(to: self) }

    func child(forKey key: some CodingKey) -> Node {
        if keyed == nil { keyed = [:] }
        let child = Node(codingPath: codingPath + [key])
        keyed![key.stringValue] = child
        return child
    }

    func appendChild() -> Node {
        if unkeyed == nil { unkeyed = [] }
        let child = Node(codingPath: codingPath + [SnapshotKey(intValue: unkeyed!.count)])
        unkeyed!.append(child)
        return child
    }

    var count: Int { unkeyed?.count ?? 0 }

    func container<Key: CodingKey>(keyedBy type: Key.Type) -> KeyedEncodingContainer<Key> {
        if keyed == nil { keyed = [:] }
        return KeyedEncodingContainer(KeyedContainer(node: self))
    }

    func unkeyedContainer() -> any UnkeyedEncodingContainer {
        if unkeyed == nil { unkeyed = [] }
        return UnkeyedContainer(node: self)
    }

    func singleValueContainer() -> any SingleValueEncodingContainer {
        SingleValueContainer(node: self)
    }
}

private struct KeyedContainer<Key: CodingKey>: KeyedEncodingContainerProtocol {
    let node: Node
    var codingPath: [any CodingKey] { node.codingPath }

    mutating func encodeNil(forKey key: Key) { node.child(forKey: key).store(.null) }
    mutating func encode(_ value: Bool, forKey key: Key) { node.child(forKey: key).store(value) }
    mutating func encode(_ value: String, forKey key: Key) { node.child(forKey: key).store(value) }
    mutating func encode(_ value: Double, forKey key: Key) { node.child(forKey: key).store(value) }
    mutating func encode(_ value: Float, forKey key: Key) { node.child(forKey: key).store(value) }
    mutating func encode(_ value: Int, forKey key: Key) { node.child(forKey: key).store(value) }
    mutating func encode(_ value: Int8, forKey key: Key) { node.child(forKey: key).store(value) }
    mutating func encode(_ value: Int16, forKey key: Key) { node.child(forKey: key).store(value) }
    mutating func encode(_ value: Int32, forKey key: Key) { node.child(forKey: key).store(value) }
    mutating func encode(_ value: Int64, forKey key: Key) { node.child(forKey: key).store(value) }
    mutating func encode(_ value: UInt, forKey key: Key) { node.child(forKey: key).store(value) }
    mutating func encode(_ value: UInt8, forKey key: Key) { node.child(forKey: key).store(value) }
    mutating func encode(_ value: UInt16, forKey key: Key) { node.child(forKey: key).store(value) }
    mutating func encode(_ value: UInt32, forKey key: Key) { node.child(forKey: key).store(value) }
    mutating func encode(_ value: UInt64, forKey key: Key) { node.child(forKey: key).store(value) }
    mutating func encode<T: Encodable>(_ value: T, forKey key: Key) throws { try node.child(forKey: key).store(value) }

    mutating func nestedContainer<NestedKey: CodingKey>(
        keyedBy keyType: NestedKey.Type, forKey key: Key
    ) -> KeyedEncodingContainer<NestedKey> {
        node.child(forKey: key).container(keyedBy: keyType)
    }

    mutating func nestedUnkeyedContainer(forKey key: Key) -> any UnkeyedEncodingContainer {
        node.child(forKey: key).unkeyedContainer()
    }

    mutating func superEncoder() -> any Encoder { node.child(forKey: SnapshotKey.super) }
    mutating func superEncoder(forKey key: Key) -> any Encoder { node.child(forKey: key) }
}

private struct UnkeyedContainer: UnkeyedEncodingContainer {
    let node: Node
    var codingPath: [any CodingKey] { node.codingPath }
    var count: Int { node.count }

    mutating func encodeNil() { node.appendChild().store(.null) }
    mutating func encode(_ value: Bool) { node.appendChild().store(value) }
    mutating func encode(_ value: String) { node.appendChild().store(value) }
    mutating func encode(_ value: Double) { node.appendChild().store(value) }
    mutating func encode(_ value: Float) { node.appendChild().store(value) }
    mutating func encode(_ value: Int) { node.appendChild().store(value) }
    mutating func encode(_ value: Int8) { node.appendChild().store(value) }
    mutating func encode(_ value: Int16) { node.appendChild().store(value) }
    mutating func encode(_ value: Int32) { node.appendChild().store(value) }
    mutating func encode(_ value: Int64) { node.appendChild().store(value) }
    mutating func encode(_ value: UInt) { node.appendChild().store(value) }
    mutating func encode(_ value: UInt8) { node.appendChild().store(value) }
    mutating func encode(_ value: UInt16) { node.appendChild().store(value) }
    mutating func encode(_ value: UInt32) { node.appendChild().store(value) }
    mutating func encode(_ value: UInt64) { node.appendChild().store(value) }
    mutating func encode<T: Encodable>(_ value: T) throws { try node.appendChild().store(value) }

    mutating func nestedContainer<NestedKey: CodingKey>(keyedBy keyType: NestedKey.Type) -> KeyedEncodingContainer<NestedKey> {
        node.appendChild().container(keyedBy: keyType)
    }

    mutating func nestedUnkeyedContainer() -> any UnkeyedEncodingContainer { node.appendChild().unkeyedContainer() }
    mutating func superEncoder() -> any Encoder { node.appendChild() }
}

private struct SingleValueContainer: SingleValueEncodingContainer {
    let node: Node
    var codingPath: [any CodingKey] { node.codingPath }

    mutating func encodeNil() { node.store(.null) }
    mutating func encode(_ value: Bool) { node.store(value) }
    mutating func encode(_ value: String) { node.store(value) }
    mutating func encode(_ value: Double) { node.store(value) }
    mutating func encode(_ value: Float) { node.store(value) }
    mutating func encode(_ value: Int) { node.store(value) }
    mutating func encode(_ value: Int8) { node.store(value) }
    mutating func encode(_ value: Int16) { node.store(value) }
    mutating func encode(_ value: Int32) { node.store(value) }
    mutating func encode(_ value: Int64) { node.store(value) }
    mutating func encode(_ value: UInt) { node.store(value) }
    mutating func encode(_ value: UInt8) { node.store(value) }
    mutating func encode(_ value: UInt16) { node.store(value) }
    mutating func encode(_ value: UInt32) { node.store(value) }
    mutating func encode(_ value: UInt64) { node.store(value) }
    mutating func encode<T: Encodable>(_ value: T) throws { try node.store(value) }
}
