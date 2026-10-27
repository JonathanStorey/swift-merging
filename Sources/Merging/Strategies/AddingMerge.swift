/// Adds both sides' changes to the base, as a counter does, so two increments of one both count. Needs a
/// base, and a whole number that would overflow is a conflict.
public struct AddingMerge: SnapshotMergeStrategy {
    public init() {}

    public func merge(base: Snapshot, ours: Snapshot, theirs: Snapshot) throws(MergeConflict<Snapshot>) -> Snapshot {
        if case .int(let original) = base, case .int(let mine) = ours, case .int(let other) = theirs {
            let (added, overflowed) = mine.addingReportingOverflow(other)
            let (sum, underflowed) = added.subtractingReportingOverflow(original)
            guard !overflowed, !underflowed else { throw MergeConflict(base: base, ours: ours, theirs: theirs) }
            return .int(sum)
        }
        guard let original = base.double, let mine = ours.double, let other = theirs.double else {
            throw MergeConflict(base: base, ours: ours, theirs: theirs)
        }
        return .double(mine + other - original)
    }
}

extension MergeStrategy where Self == AddingMerge {
    /// A counter: both sides' increments count. Needs a base.
    public static var adding: AddingMerge { AddingMerge() }
}

extension Merged where Strategy == AddingMerge {
    public init(wrappedValue: Value, _ strategy: AddingMerge) where Value: AdditiveArithmetic {
        self.init(wrappedValue: wrappedValue, unchecked: strategy)
    }
}
