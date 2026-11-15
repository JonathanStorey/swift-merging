/// Merges a `Codable` value node by node through its stored form, a structured merge: a node only one side
/// changed keeps that side. Where both changed it, an object merges key by key, an array element by
/// element, a `Set` by membership, a `Dictionary` by key, and anything else can't be merged. The result
/// must decode, or the merge is `nil`. Without a base, only what's equal merges.
///
/// ```swift
/// @Merged(.byNode) var address: Address = Address()
/// CodableNodeMerge<Address>().merge(base: original, ours: mine, theirs: yours)
/// ```
///
/// It encodes and decodes on every merge, which fits syncing better than tight loops.
public struct CodableNodeMerge<Value: Codable & Sendable>: MergeStrategy {
    public init() {}

    public func merge(base: Value, ours: Value, theirs: Value) -> Value? {
        do {
            let encoder = TreeEncoder()
            let merged = try encoder.encode(ours).merging(with: encoder.encode(theirs), from: encoder.encode(base))
            return try TreeDecoder().decode(Value.self, from: merged)
        } catch {
            return nil
        }
    }

    public func merge(ours: Value, theirs: Value) -> Value? {
        do {
            let encoder = TreeEncoder()
            let merged = try encoder.encode(ours).merging(with: encoder.encode(theirs))
            return try TreeDecoder().decode(Value.self, from: merged)
        } catch {
            return nil
        }
    }
}
