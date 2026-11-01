/// How one property merges, chosen with `@Merged`, for a property whose type merges differently in
/// different places, such as an `Int` that's a counter in one and a high score in another. A strategy
/// decides only when both sides changed the property.
///
/// Implement the three-way merge, and the two-way merge too if the strategy needs no ancestor. A typed
/// strategy's value is the property's type. A `TreeMergeStrategy` merges a property's stored form instead.
///
/// ```swift
/// struct LongerMerge: MergeStrategy {
///     typealias Value = String
///
///     func merge(base: String, ours: String, theirs: String) -> String? {
///         ours.count >= theirs.count ? ours : theirs
///     }
/// }
/// ```
///
/// A strategy returns `nil` when the versions can't be merged. It's made with `init()` when a value is
/// decoded, so it holds no settings of its own.
public protocol MergeStrategy<Value>: Sendable {
    associatedtype Value: Sendable

    init()
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
    /// Without a base, equal values merge, as they do inside a whole value's merge, and anything else is
    /// `nil`.
    public func merge(ours: Value, theirs: Value) -> Value? {
        ours == theirs ? ours : nil
    }
}
