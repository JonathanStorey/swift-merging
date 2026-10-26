/// Merges a set, or an array treated as one, so that no addition is lost. With a base, it merges by
/// membership, keeping what either side added and dropping what either removed. Without one, there's no
/// telling an addition from a removal, so it keeps every element either side has: ours in order, then
/// theirs that ours lacks.
public struct UnionMerge: MergeStrategy {
    public typealias Value = Snapshot

    public init() {}

    public func merge(base: Snapshot, ours: Snapshot, theirs: Snapshot) throws(MergeConflict<Snapshot>) -> Snapshot {
        try MembershipMerge().merge(base: base, ours: ours, theirs: theirs)
    }

    public func merge(ours: Snapshot, theirs: Snapshot) throws(MergeConflict<Snapshot>) -> Snapshot {
        guard let mine = ours.array, let other = theirs.array else { throw MergeConflict(ours: ours, theirs: theirs) }
        let mineKeys = Set(mine.map { MergeTree($0).canonical })
        return .array(mine + other.filter { !mineKeys.contains(MergeTree($0).canonical) })
    }
}

extension MergeStrategy where Self == UnionMerge {
    /// Keeps every addition, such as tags or recipients. Merges without a base too.
    public static var union: UnionMerge { UnionMerge() }
}
