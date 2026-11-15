/// Merges a set so that no addition is lost, such as tags or recipients. With a base, it merges by
/// membership, keeping what either side added and dropping what either removed. Without one, there's no
/// telling an addition from a removal, so it keeps every element either side has.
///
/// ```swift
/// @Merged(.union) var recipients: Set<String> = []
/// ```
public struct SetAlgebraUnionMerge<Value: SetAlgebra & Sendable>: MergeStrategy {
    public init() {}

    public func merge(base: Value, ours: Value, theirs: Value) -> Value? {
        .mergedByMembership(base: base, ours: ours, theirs: theirs)
    }

    public func merge(ours: Value, theirs: Value) -> Value? { ours.union(theirs) }
}
