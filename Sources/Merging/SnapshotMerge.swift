/// Two versions of part of a snapshot that couldn't be merged.
struct SnapshotConflict: Error {}

extension Snapshot {
    /// Merges `theirs` into this snapshot, which is ours, knowing their common ancestor. Objects merge key by
    /// key and arrays element by element, and anything else keeps the side that changed.
    func merging(_ theirs: Snapshot, base: Snapshot) throws(SnapshotConflict) -> Snapshot {
        if self == theirs || theirs == base { return self }
        if self == base { return theirs }
        switch (self, theirs, base) {
        case let (.object(ours), .object(theirs), .object(base)): return .object(try Self.merge(ours, theirs, base: base))
        case let (.array(ours), .array(theirs), .array(base)): return .array(try Self.merge(ours, theirs, base: base))
        default: throw SnapshotConflict()
        }
    }

    /// Merges key by key. Keys both sides added merge without a base, so they must match, and a key one side
    /// removed while the other changed it is a conflict.
    private static func merge(
        _ ours: [String: Snapshot], _ theirs: [String: Snapshot], base: [String: Snapshot]
    ) throws(SnapshotConflict) -> [String: Snapshot] {
        var merged: [String: Snapshot] = [:]
        for key in Set(ours.keys).union(theirs.keys).union(base.keys) {
            let (mine, other, original) = (ours[key], theirs[key], base[key])
            if mine == other || other == original {
                merged[key] = mine
            } else if mine == original {
                merged[key] = other
            } else if let mine, let other, let original {
                merged[key] = try mine.merging(other, base: original)
            } else {
                throw SnapshotConflict()
            }
        }
        return merged
    }

    /// Merges element by element, like a three-way merge of lines. An element either side removed is removed,
    /// and what each side inserted goes where it was inserted, ours first. Where both sides replaced the same
    /// element with one element each, those two merge; any other replacement both sides made is a conflict.
    private static func merge(_ ours: [Snapshot], _ theirs: [Snapshot], base: [Snapshot]) throws(SnapshotConflict) -> [Snapshot] {
        let mine = Edits(ours, from: base)
        let other = Edits(theirs, from: base)
        var merged: [Snapshot] = []
        for index in 0...base.count {
            let (inserted, theirsInserted) = (mine.inserted[index], other.inserted[index])
            if inserted == theirsInserted || theirsInserted.isEmpty {
                merged += inserted
            } else if inserted.isEmpty {
                merged += theirsInserted
            } else if index < base.count, mine.removed.contains(index), other.removed.contains(index) {
                // Both replaced the element that follows.
                guard inserted.count == 1, theirsInserted.count == 1 else { throw SnapshotConflict() }
                merged.append(try inserted[0].merging(theirsInserted[0], base: base[index]))
            } else {
                merged += inserted + theirsInserted
            }
            if index < base.count, !mine.removed.contains(index), !other.removed.contains(index) {
                merged.append(base[index])
            }
        }
        return merged
    }
}

/// One side's changes to an array: the base elements it removed, and what it inserted before each base
/// element, with the last slot for what it added at the end. A changed element is removed, with its new
/// version inserted before it.
private struct Edits {
    var removed: Set<Int> = []
    var inserted: [[Snapshot]]

    init(_ side: [Snapshot], from base: [Snapshot]) {
        inserted = Array(repeating: [], count: base.count + 1)
        var insertedOffsets: Set<Int> = []
        for change in side.difference(from: base) {
            switch change {
            case .remove(let offset, _, _): removed.insert(offset)
            case .insert(let offset, _, _): insertedOffsets.insert(offset)
            }
        }
        // The side's other elements are the base's kept ones, in order.
        var next = 0
        for index in 0...base.count {
            while insertedOffsets.contains(next) {
                inserted[index].append(side[next])
                next += 1
            }
            if index < base.count, !removed.contains(index) { next += 1 }
        }
    }
}
