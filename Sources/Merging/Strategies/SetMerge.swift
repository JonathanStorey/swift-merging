/// Merges a set, or an array treated as one, by what each side added and removed: an element is kept if
/// either side added it, and removed if either side removed it. Order doesn't matter. Without a base,
/// only equal sets merge.
public struct SetMerge: MergeStrategy {
    public typealias Value = Snapshot

    public init() {}

    public func merge(base: Snapshot, ours: Snapshot, theirs: Snapshot) throws(MergeConflict<Snapshot>) -> Snapshot {
        do {
            return Snapshot(try MergeTree.mergeSets(MergeTree(ours), MergeTree(theirs), base: MergeTree(base)))
        } catch {
            throw MergeConflict(base: base, ours: ours, theirs: theirs)
        }
    }

    public func merge(ours: Snapshot, theirs: Snapshot) throws(MergeConflict<Snapshot>) -> Snapshot {
        do {
            return Snapshot(try MergeTree.mergeSets(MergeTree(ours), MergeTree(theirs), base: nil))
        } catch {
            throw MergeConflict(ours: ours, theirs: theirs)
        }
    }
}

extension MergeStrategy where Self == SetMerge {
    /// Merges an array as a set, such as tags, ignoring its order.
    public static var asSet: SetMerge { SetMerge() }
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
