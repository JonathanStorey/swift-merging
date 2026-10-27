/// `true` if either side is. Merges with or without a base.
public struct TrueWinsMerge: SnapshotMergeStrategy {
    public init() {}

    public func merge(base: Snapshot, ours: Snapshot, theirs: Snapshot) throws(MergeConflict<Snapshot>) -> Snapshot {
        try merge(ours: ours, theirs: theirs)
    }

    public func merge(ours: Snapshot, theirs: Snapshot) throws(MergeConflict<Snapshot>) -> Snapshot {
        guard let mine = ours.bool, let other = theirs.bool else { throw MergeConflict(ours: ours, theirs: theirs) }
        return .bool(mine || other)
    }
}

extension MergeStrategy where Self == TrueWinsMerge {
    /// A flag anyone can set, such as "flagged" or "read".
    public static var trueWins: TrueWinsMerge { TrueWinsMerge() }
}

extension Merged where Strategy == TrueWinsMerge {
    public init(wrappedValue: Value, _ strategy: TrueWinsMerge) where Value == Bool {
        self.init(wrappedValue: wrappedValue, unchecked: strategy)
    }
}
