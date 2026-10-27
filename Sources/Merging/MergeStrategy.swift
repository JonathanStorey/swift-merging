/// How one property merges, chosen with `@Merged`, for a property whose type merges differently in
/// different places, such as an `Int` that's a counter in one and a high score in another. A strategy
/// decides only when both sides changed the property.
///
/// Implement the three-way merge, and the two-way merge too if the strategy needs no ancestor. A typed
/// strategy's value is the property's type. A `SnapshotMergeStrategy` merges a property's stored form instead,
/// as the standard ones such as `.maximum` do.
///
/// ```swift
/// struct LongerMerge: MergeStrategy {
///     typealias Value = String
///
///     func merge(base: String, ours: String, theirs: String) -> String {
///         ours.count >= theirs.count ? ours : theirs
///     }
/// }
/// ```
///
/// A strategy is made with `init()` when a value is decoded, so it holds no settings of its own. A
/// non-generic strategy whose merge doesn't throw names its value with `typealias Value`.
public protocol MergeStrategy<Value>: Sendable {
    associatedtype Value: Sendable

    init()
    func merge(base: Value, ours: Value, theirs: Value) throws(MergeConflict<Value>) -> Value
    func merge(ours: Value, theirs: Value) throws(MergeConflict<Value>) -> Value
}

extension MergeStrategy {
    public func merge(ours: Value, theirs: Value) throws(MergeConflict<Value>) -> Value {
        throw MergeConflict(ours: ours, theirs: theirs)
    }
}

/// The versions that couldn't be merged. `base` is `nil` for a two-way merge.
public struct MergeConflict<Value: Sendable>: Error {
    public let base: Value?
    public let ours: Value
    public let theirs: Value

    public init(base: Value? = nil, ours: Value, theirs: Value) {
        self.base = base
        self.ours = ours
        self.theirs = theirs
    }
}
