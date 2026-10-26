/// How one property merges, chosen with `@Merged`, for a property whose type merges differently in
/// different places, such as an `Int` that's a counter in one and a high score in another. Implement the
/// two-way merge, and the three-way merge uses it by default.
///
/// ```swift
/// struct MaxMerge<Value: Comparable & Sendable>: MergeStrategy {
///     func merge(ours: Value, theirs: Value) -> Value { max(ours, theirs) }
/// }
/// ```
///
/// A strategy that only makes sense with an ancestor, such as adding both sides' changes to a counter,
/// implements the three-way merge and throws from the two-way one. A non-generic strategy whose merge
/// doesn't throw names its value with `typealias Value`.
public protocol MergeStrategy<Value>: Sendable {
    associatedtype Value: Sendable

    func merge(ours: Value, theirs: Value) throws(MergeConflict<Value>) -> Value
    func merge(base: Value, ours: Value, theirs: Value) throws(MergeConflict<Value>) -> Value
}

extension MergeStrategy {
    public func merge(base: Value, ours: Value, theirs: Value) throws(MergeConflict<Value>) -> Value {
        try merge(ours: ours, theirs: theirs)
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
