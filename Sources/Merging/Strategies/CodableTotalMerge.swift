/// Merges a `Codable` value node by node like `CodableNodeMerge`, but always merges: every change that
/// doesn't clash still applies, from both sides, and a node both sides changed differently takes the
/// favored side, as `git merge -X theirs` does. A result that doesn't decode keeps that whole side.
///
/// ```swift
/// @Merged(.total(favoring: .theirs)) var place: Place = Place()
/// CodableTotalMerge<Note>(favoring: oursIsNewer ? .ours : .theirs).merge(base: base, ours: mine, theirs: yours)
/// ```
public struct CodableTotalMerge<Value: Codable & Sendable>: MergeStrategy {
    let side: MergeSide

    public init(favoring side: MergeSide) {
        self.side = side
    }

    public func merge(base: Value, ours: Value, theirs: Value) -> Value? {
        do {
            let encoder = TreeEncoder()
            let merged = try encoder.encode(ours).merging(with: encoder.encode(theirs), from: encoder.encode(base), favoring: side)
            return try TreeDecoder().decode(Value.self, from: merged)
        } catch {
            return side == .ours ? ours : theirs
        }
    }

    public func merge(ours: Value, theirs: Value) -> Value? {
        do {
            let encoder = TreeEncoder()
            let merged = try encoder.encode(ours).merging(with: encoder.encode(theirs), favoring: side)
            return try TreeDecoder().decode(Value.self, from: merged)
        } catch {
            return side == .ours ? ours : theirs
        }
    }
}
