/// Keeps the larger value, by the type's own `<`: a high score, the furthest progress, the latest date.
/// Merges with or without a base.
///
/// ```swift
/// @Merged(.maximum) var highScore = 0
/// @Merged(.maximum) var level: Level = Level(number: 1)     // uses Level's own <
/// ```
public struct ComparableMaximumMerge<Value: Comparable & Sendable>: MergeStrategy {
    public init() {}

    public func merge(base: Value, ours: Value, theirs: Value) -> Value? { merge(ours: ours, theirs: theirs) }

    public func merge(ours: Value, theirs: Value) -> Value? { ours < theirs ? theirs : ours }
}
