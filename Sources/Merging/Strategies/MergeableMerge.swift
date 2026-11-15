/// Merges a `Mergeable` value by its own `merging` functions, favoring one side where both changed the
/// same thing. Merges with or without a base. A merge that throws is `nil`.
///
/// ```swift
/// @Merged(.mergeable(favoring: .theirs)) var tally: Tally = Tally()
/// ```
public struct MergeableMerge<Value: Mergeable & Sendable>: MergeStrategy where Value.MergeBase == Value {
    let side: MergeSide

    public init(favoring side: MergeSide) {
        self.side = side
    }

    public func merge(base: Value, ours: Value, theirs: Value) -> Value? {
        try? Value.merge(base: base, ours: ours, theirs: theirs, favoring: side)
    }

    public func merge(ours: Value, theirs: Value) -> Value? {
        try? Value.merge(ours: ours, theirs: theirs, favoring: side)
    }
}
