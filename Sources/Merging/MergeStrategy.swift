/// How one property merges, chosen with `@Merged`. A strategy decides only when both sides changed the
/// property: a side only one changed keeps that side.
///
/// Implement the three-way merge, and the two-way merge too if the strategy needs no ancestor. A strategy
/// is a plain value, so it can hold settings of its own.
///
/// ```swift
/// struct LongerMerge: MergeStrategy {
///     func merge(base: String, ours: String, theirs: String) -> String? {
///         ours.count >= theirs.count ? ours : theirs
///     }
/// }
///
/// @Merged(LongerMerge()) var title = ""
/// ```
///
/// A strategy returns `nil` when the versions can't be merged.
public protocol MergeStrategy<Value>: Sendable {
    associatedtype Value: Sendable

    /// The merged value, or `nil` if the versions can't be merged.
    func merge(base: Value, ours: Value, theirs: Value) -> Value?
    /// The merged value without a base, or `nil` if the versions can't be merged without one.
    func merge(ours: Value, theirs: Value) -> Value?
}

extension MergeStrategy {
    /// Without a base, a strategy can't tell what either side changed, so this is `nil`.
    public func merge(ours: Value, theirs: Value) -> Value? { nil }
}

extension MergeStrategy where Value: Equatable {
    /// Without a base, equal values merge and anything else is `nil`.
    public func merge(ours: Value, theirs: Value) -> Value? {
        ours == theirs ? ours : nil
    }
}
