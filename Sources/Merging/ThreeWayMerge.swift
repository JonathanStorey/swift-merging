/// The default strategy for any `Equatable` value. Two-way, equal values merge and different ones
/// conflict. Three-way, a value only one side changed keeps that change, and a value both changed
/// differently conflicts.
public struct ThreeWayMerge<Value: Equatable & Sendable>: MergeStrategy {
    public init() {}

    public func merge(ours: Value, theirs: Value) throws(MergeConflict<Value>) -> Value {
        guard ours == theirs else { throw MergeConflict(ours: ours, theirs: theirs) }
        return ours
    }

    public func merge(base: Value, ours: Value, theirs: Value) throws(MergeConflict<Value>) -> Value {
        if ours == theirs || theirs == base { return ours }
        if ours == base { return theirs }
        throw MergeConflict(base: base, ours: ours, theirs: theirs)
    }
}
