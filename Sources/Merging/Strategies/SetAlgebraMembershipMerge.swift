/// Merges a set by what each side added and removed: an element is kept if either side added it, and
/// removed if either side removed it. Works on `Set` and any `OptionSet`. Without a base, only equal sets
/// merge.
///
/// ```swift
/// @Merged(.byMembership) var tags: Set<String> = []
/// @Merged(.byMembership) var shipping: Shipping = []     // an OptionSet
/// ```
public struct SetAlgebraMembershipMerge<Value: SetAlgebra & Sendable>: MergeStrategy {
    public init() {}

    public func merge(base: Value, ours: Value, theirs: Value) -> Value? {
        .mergedByMembership(base: base, ours: ours, theirs: theirs)
    }
}

extension SetAlgebra {
    /// What both sides kept, plus what either added.
    static func mergedByMembership(base: Self, ours: Self, theirs: Self) -> Self {
        ours.intersection(theirs).union(ours.subtracting(base)).union(theirs.subtracting(base))
    }
}
