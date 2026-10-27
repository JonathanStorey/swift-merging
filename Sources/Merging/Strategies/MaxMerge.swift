/// Keeps the larger value: numbers by value, text alphabetically, and dates by time, since they're stored
/// as numbers. Merges with or without a base. Anything else is a conflict, so for a type of your own,
/// write a typed strategy that uses its `<`.
public struct MaxMerge: SnapshotMergeStrategy {
    public init() {}

    public func merge(base: Snapshot, ours: Snapshot, theirs: Snapshot) throws(MergeConflict<Snapshot>) -> Snapshot {
        try merge(ours: ours, theirs: theirs)
    }

    public func merge(ours: Snapshot, theirs: Snapshot) throws(MergeConflict<Snapshot>) -> Snapshot {
        switch (ours, theirs) {
        case let (.string(mine), .string(other)): return mine < other ? theirs : ours
        case let (.int(mine), .int(other)): return mine < other ? theirs : ours
        default:
            guard let mine = ours.double, let other = theirs.double else { throw MergeConflict(ours: ours, theirs: theirs) }
            return mine < other ? theirs : ours
        }
    }
}

// Named `maximum`, not `max`, since a static `max` would hide `Swift.max` inside every strategy.
extension MergeStrategy where Self == MaxMerge {
    /// Keeps the larger value: a high score, the furthest progress, the latest date.
    public static var maximum: MaxMerge { MaxMerge() }
}

extension Merged where Strategy == MaxMerge {
    public init(wrappedValue: Value, _ strategy: MaxMerge) where Value: Comparable {
        self.init(wrappedValue: wrappedValue, unchecked: strategy)
    }
}
