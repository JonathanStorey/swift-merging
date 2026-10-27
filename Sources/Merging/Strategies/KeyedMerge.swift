/// Merges a dictionary key by key, whatever the key's type: a key only one side changed, added, or removed
/// keeps that side, and a key both sides changed merges its values.
public struct KeyedMerge: SnapshotMergeStrategy {
    public init() {}

    public func merge(base: Snapshot, ours: Snapshot, theirs: Snapshot) throws(MergeConflict<Snapshot>) -> Snapshot {
        do {
            return Snapshot(try MergeTree.mergeDictionaries(MergeTree(ours), MergeTree(theirs), base: MergeTree(base)))
        } catch {
            throw MergeConflict(base: base, ours: ours, theirs: theirs)
        }
    }

    public func merge(ours: Snapshot, theirs: Snapshot) throws(MergeConflict<Snapshot>) -> Snapshot {
        do {
            return Snapshot(try MergeTree.mergeDictionaries(MergeTree(ours), MergeTree(theirs), base: nil))
        } catch {
            throw MergeConflict(ours: ours, theirs: theirs)
        }
    }
}

extension MergeStrategy where Self == KeyedMerge {
    /// Merges a dictionary key by key.
    public static var byKey: KeyedMerge { KeyedMerge() }
}

/// Every dictionary merges by key. One with string or integer keys encodes as an object, which merges by
/// key anyway. Any other encodes as a flat array of keys and values, which would mangle in an array merge.
/// Merging the tree rather than a snapshot keeps the rules of the values inside.
extension Dictionary: DefaultMergeRule {
    static var defaultMergeRule: MergeRule {
        MergeRule { ours, theirs, base throws(MergeConflict<MergeTree>) in try MergeTree.mergeDictionaries(ours, theirs, base: base) }
    }
}

extension MergeTree {
    static func mergeDictionaries(_ ours: MergeTree, _ theirs: MergeTree, base: MergeTree?) throws(MergeConflict<MergeTree>) -> MergeTree {
        guard case .array = ours else {
            if let base { return try ours.merging(theirs, base: base) }
            return try ours.merging(theirs)
        }
        // Keys line up by their canonical text, so any key works.
        var keys: [String: MergeTree] = [:]
        func object(_ tree: MergeTree) throws(MergeConflict<MergeTree>) -> MergeTree {
            guard case .array(let flat) = tree, flat.count.isMultiple(of: 2) else { throw MergeConflict(ours: tree, theirs: tree) }
            var object: [String: MergeTree] = [:]
            for index in stride(from: 0, to: flat.count, by: 2) {
                let text = flat[index].canonical
                keys[text] = flat[index]
                object[text] = flat[index + 1]
            }
            return .object(object)
        }
        let (mine, other) = (try object(ours), try object(theirs))
        let merged = if let base { try mine.merging(other, base: object(base)) } else { try mine.merging(other) }
        guard case .object(let entries) = merged else { return ours }
        return .array(entries.flatMap { [keys[$0.key]!, $0.value] })
    }
}

extension Merged where Strategy == KeyedMerge {
    public init<Key, Element>(wrappedValue: Value, _ strategy: KeyedMerge) where Value == [Key: Element] {
        self.init(wrappedValue: wrappedValue, unchecked: strategy)
    }
}
