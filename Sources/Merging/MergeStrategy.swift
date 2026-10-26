/// Merges two or three versions of a value. Implement the two-way merge, and the three-way merge, which
/// is called whenever the common ancestor is known, uses it by default. Throwing a `MergeConflict` is the
/// only way to say the versions can't be merged.
///
/// ```swift
/// struct MaxMerge<Value: Comparable & Sendable>: MergeStrategy {
///     func merge(ours: Value, theirs: Value) -> Value { max(ours, theirs) }
/// }
/// ```
///
/// A strategy that only makes sense with an ancestor, such as one that adds both sides' changes to a
/// counter, implements the three-way merge and throws from the two-way one.
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

/// The versions a strategy couldn't merge. `base` is `nil` for a two-way merge.
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
