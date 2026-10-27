/// `true` if either side is. Merges with or without a base.
public struct TrueWinsMerge: TreeMergeStrategy {
    public init() {}

    public func merge(base: CodableTree, ours: CodableTree, theirs: CodableTree) throws(MergeConflict<CodableTree>) -> CodableTree {
        try merge(ours: ours, theirs: theirs)
    }

    public func merge(ours: CodableTree, theirs: CodableTree) throws(MergeConflict<CodableTree>) -> CodableTree {
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
