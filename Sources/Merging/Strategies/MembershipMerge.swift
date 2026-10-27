/// Merges a set, or an array treated as one, by what each side added and removed: an element is kept if
/// either side added it, and removed if either side removed it. Order doesn't matter. Without a base,
/// only equal sets merge.
public struct MembershipMerge: TreeMergeStrategy {
    public init() {}

    public func merge(base: CodableTree, ours: CodableTree, theirs: CodableTree) throws(MergeConflict<CodableTree>) -> CodableTree {
        do {
            return CodableTree(try MergeTree.mergeSets(MergeTree(ours), MergeTree(theirs), base: MergeTree(base)))
        } catch {
            throw MergeConflict(base: base, ours: ours, theirs: theirs)
        }
    }

    public func merge(ours: CodableTree, theirs: CodableTree) throws(MergeConflict<CodableTree>) -> CodableTree {
        do {
            return CodableTree(try MergeTree.mergeSets(MergeTree(ours), MergeTree(theirs), base: nil))
        } catch {
            throw MergeConflict(ours: ours, theirs: theirs)
        }
    }
}

extension MergeStrategy where Self == MembershipMerge {
    /// Merges who's in a collection, such as tags, ignoring its order.
    public static var byMembership: MembershipMerge { MembershipMerge() }
}

/// Every set merges as one, since it encodes in no particular order.
extension Set: DefaultMergeRule {
    static var defaultMergeRule: MergeRule {
        MergeRule { ours, theirs, base throws(MergeConflict<MergeTree>) in try MergeTree.mergeSets(ours, theirs, base: base) }
    }
}

extension MergeTree {
    static func mergeSets(_ ours: MergeTree, _ theirs: MergeTree, base: MergeTree?) throws(MergeConflict<MergeTree>) -> MergeTree {
        guard case .array(let mine) = ours, case .array(let other) = theirs else { throw MergeConflict(base: base, ours: ours, theirs: theirs) }
        let (mineKeys, otherKeys) = (Set(mine.map(\.canonical)), Set(other.map(\.canonical)))
        guard let base else {
            guard mineKeys == otherKeys else { throw MergeConflict(ours: ours, theirs: theirs) }
            return ours
        }
        guard case .array(let original) = base else { throw MergeConflict(base: base, ours: ours, theirs: theirs) }
        let baseKeys = Set(original.map(\.canonical))
        let kept = mine.filter { otherKeys.contains($0.canonical) || !baseKeys.contains($0.canonical) }
        let added = other.filter { !mineKeys.contains($0.canonical) && !baseKeys.contains($0.canonical) }
        return .array(kept + added)
    }
}

extension Merged where Strategy == MembershipMerge {
    public init(wrappedValue: Value, _ strategy: MembershipMerge) where Value: Collection {
        self.init(wrappedValue: wrappedValue, unchecked: strategy)
    }
}
