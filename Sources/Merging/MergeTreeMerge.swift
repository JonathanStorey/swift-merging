/// A tree merges like any other value, and a conflict holds the part that clashed, with an absent
/// object key shown as `null`.
extension MergeTree: Mergeable {
    /// Merges `theirs` into this tree, which is ours, knowing their common ancestor. A part only one side
    /// changed keeps that side. Where both did, a part with a rule merges by it, objects merge key by key and
    /// arrays element by element, and anything else is a conflict.
    func merging(_ theirs: MergeTree, base: MergeTree) throws(MergeConflict<MergeTree>) -> MergeTree {
        if theirs == base { return self }
        if self == base { return theirs }
        // Both sides changed it. Equal changes still go to a rule, since a counter both sides added one to
        // has gone up by two.
        switch (self, theirs, base) {
        case let (.merged(ours, rule), .merged(theirs, _), .merged(base, _)): return .merged(try rule.merge(ours, theirs, base), rule)
        case let (.object(ours), .object(theirs), .object(base)): return .object(try Self.merge(ours, theirs, base: base))
        case let (.array(ours), .array(theirs), .array(base)): return .array(try Self.merge(ours, theirs, base: base))
        default:
            guard self == theirs else { throw MergeConflict(base: base, ours: self, theirs: theirs) }
            return self
        }
    }

    /// Merges without a common ancestor, so only what's equal, or what has a rule for merging without one.
    func merging(_ theirs: MergeTree) throws(MergeConflict<MergeTree>) -> MergeTree {
        if self == theirs { return self }
        switch (self, theirs) {
        case let (.merged(ours, rule), .merged(theirs, _)):
            return .merged(try rule.merge(ours, theirs, nil), rule)
        case let (.object(ours), .object(theirs)) where Set(ours.keys) == Set(theirs.keys):
            var merged: [String: MergeTree] = [:]
            for (key, value) in ours { merged[key] = try value.merging(theirs[key]!) }
            return .object(merged)
        case let (.array(ours), .array(theirs)) where ours.count == theirs.count:
            var merged: [MergeTree] = []
            for (value, other) in zip(ours, theirs) { merged.append(try value.merging(other)) }
            return .array(merged)
        default:
            throw MergeConflict(ours: self, theirs: theirs)
        }
    }

    /// Merges key by key. A key both sides added merges without a base, and a key one side removed while
    /// the other changed it is a conflict.
    private static func merge(
        _ ours: [String: MergeTree], _ theirs: [String: MergeTree], base: [String: MergeTree]
    ) throws(MergeConflict<MergeTree>) -> [String: MergeTree] {
        var merged: [String: MergeTree] = [:]
        for key in Set(ours.keys).union(theirs.keys).union(base.keys) {
            let (mine, other, original) = (ours[key], theirs[key], base[key])
            if other == original {
                merged[key] = mine
            } else if mine == original {
                merged[key] = other
            } else if let mine, let other {
                if let original {
                    merged[key] = try mine.merging(other, base: original)
                } else {
                    merged[key] = try mine.merging(other)
                }
            } else if mine != other {
                throw MergeConflict(base: original, ours: mine ?? .null, theirs: other ?? .null)
            }
        }
        return merged
    }

    /// Merges element by element, like a three-way merge of lines. An element either side removed is removed,
    /// and what each side inserted goes where it was inserted, ours first. Where both sides replaced the same
    /// element with one element each, those two merge; any other replacement both sides made is a conflict.
    private static func merge(_ ours: [MergeTree], _ theirs: [MergeTree], base: [MergeTree]) throws(MergeConflict<MergeTree>) -> [MergeTree] {
        let mine = Edits(ours, from: base)
        let other = Edits(theirs, from: base)
        var merged: [MergeTree] = []
        for index in 0...base.count {
            let (inserted, theirsInserted) = (mine.inserted[index], other.inserted[index])
            if inserted == theirsInserted || theirsInserted.isEmpty {
                merged += inserted
            } else if inserted.isEmpty {
                merged += theirsInserted
            } else if index < base.count, mine.removed.contains(index), other.removed.contains(index) {
                // Both replaced the element that follows.
                guard inserted.count == 1, theirsInserted.count == 1 else {
                    throw MergeConflict(base: base[index], ours: .array(inserted), theirs: .array(theirsInserted))
                }
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
    var inserted: [[MergeTree]]

    init(_ side: [MergeTree], from base: [MergeTree]) {
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
