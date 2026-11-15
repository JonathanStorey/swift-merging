/// A tree merges by its shape, and throws a `MergeClash` where two versions of a part can't be merged.
extension MergeTree {
    func merging(with theirs: MergeTree, from base: MergeTree) throws(MergeClash) -> MergeTree {
        try merging(with: theirs, from: base, favoring: nil)
    }

    func merging(with theirs: MergeTree) throws(MergeClash) -> MergeTree {
        try merging(with: theirs, favoring: nil)
    }

    /// Merges `theirs` into this tree, which is ours, knowing their common ancestor. A part only one side
    /// changed keeps that side. Where both did, a set merges by membership and a dictionary by key, objects merge key by key and
    /// arrays element by element, and anything else is a conflict, or keeps `side` when there is one.
    func merging(with theirs: MergeTree, from base: MergeTree, favoring side: MergeSide?) throws(MergeClash) -> MergeTree {
        if theirs == base { return self }
        if self == base { return theirs }
        do throws(MergeClash) {
            // Both sides changed it.
            switch (self, theirs, base) {
            case let (.merged(ours, kind), .merged(theirs, _), .merged(base, _)): return .merged(try kind.merge(ours, theirs, base: base), kind)
            case let (.object(ours), .object(theirs), .object(base)): return .object(try Self.merge(ours, theirs, base: base, favoring: side))
            case let (.array(ours), .array(theirs), .array(base)): return .array(try Self.merge(ours, theirs, base: base, favoring: side))
            default:
                guard self == theirs else { throw MergeClash() }
                return self
            }
        } catch {
            guard let side else { throw error }
            return side == .ours ? self : theirs
        }
    }

    /// Merges without a common ancestor, so only what's equal: objects with the same keys, arrays of the
    /// same length, and sets with the same elements in any order.
    /// Anything else is a conflict, or keeps `side` when there is one.
    func merging(with theirs: MergeTree, favoring side: MergeSide?) throws(MergeClash) -> MergeTree {
        if self == theirs { return self }
        do throws(MergeClash) {
            switch (self, theirs) {
            case let (.merged(ours, kind), .merged(theirs, _)):
                return .merged(try kind.merge(ours, theirs, base: nil), kind)
            case let (.object(ours), .object(theirs)) where Set(ours.keys) == Set(theirs.keys):
                var merged: [String: MergeTree] = [:]
                for (key, value) in ours { merged[key] = try value.merging(with: theirs[key]!, favoring: side) }
                return .object(merged)
            case let (.array(ours), .array(theirs)) where ours.count == theirs.count:
                var merged: [MergeTree] = []
                for (value, other) in zip(ours, theirs) { merged.append(try value.merging(with: other, favoring: side)) }
                return .array(merged)
            default:
                throw MergeClash()
            }
        } catch {
            guard let side else { throw error }
            return side == .ours ? self : theirs
        }
    }

    /// Merges key by key. A key both sides added merges without a base, and a key one side removed while
    /// the other changed it is a conflict.
    private static func merge(
        _ ours: [String: MergeTree], _ theirs: [String: MergeTree], base: [String: MergeTree], favoring side: MergeSide?
    ) throws(MergeClash) -> [String: MergeTree] {
        var merged: [String: MergeTree] = [:]
        for key in Set(ours.keys).union(theirs.keys).union(base.keys) {
            let (mine, other, original) = (ours[key], theirs[key], base[key])
            if other == original {
                merged[key] = mine
            } else if mine == original {
                merged[key] = other
            } else if let mine, let other {
                if let original {
                    merged[key] = try mine.merging(with: other, from: original, favoring: side)
                } else {
                    merged[key] = try mine.merging(with: other, favoring: side)
                }
            } else if let side, mine != other {
                merged[key] = side == .ours ? mine : other
            } else if mine != other {
                throw MergeClash()
            }
        }
        return merged
    }

    /// Merges element by element, like a three-way merge of lines, with an element both sides replaced
    /// merging by its shape.
    private static func merge(
        _ ours: [MergeTree], _ theirs: [MergeTree], base: [MergeTree], favoring side: MergeSide?
    ) throws(MergeClash) -> [MergeTree] {
        let merged = ours.mergingElements(with: theirs, from: base) { ours, theirs, base in
            try? ours.merging(with: theirs, from: base, favoring: side)
        }
        guard let merged else { throw MergeClash() }
        return merged
    }
}

extension MergeKind {
    /// Merges two versions of a part of this kind, with or without a base.
    func merge(_ ours: MergeTree, _ theirs: MergeTree, base: MergeTree?) throws(MergeClash) -> MergeTree {
        switch self {
        case .set: try MergeTree.mergeSets(ours, theirs, base: base)
        case .dictionary: try MergeTree.mergeDictionaries(ours, theirs, base: base)
        }
    }
}

extension MergeTree {
    /// Merges a set by membership, matching elements by their canonical text, since a set encodes in no
    /// particular order. Without a base, only sets with the same elements merge.
    fileprivate static func mergeSets(_ ours: MergeTree, _ theirs: MergeTree, base: MergeTree?) throws(MergeClash) -> MergeTree {
        guard case .array(let mine) = ours, case .array(let other) = theirs else { throw MergeClash() }
        let (mineKeys, otherKeys) = (Set(mine.map(\.canonical)), Set(other.map(\.canonical)))
        guard let base else {
            guard mineKeys == otherKeys else { throw MergeClash() }
            return ours
        }
        guard case .array(let original) = base else { throw MergeClash() }
        let baseKeys = Set(original.map(\.canonical))
        let kept = mine.filter { otherKeys.contains($0.canonical) || !baseKeys.contains($0.canonical) }
        let added = other.filter { !mineKeys.contains($0.canonical) && !baseKeys.contains($0.canonical) }
        return .array(kept + added)
    }

    /// Merges a dictionary key by key. One with string or integer keys is already an object. Any other is a
    /// flat array of keys and values, which merges as an object keyed by each key's canonical text.
    fileprivate static func mergeDictionaries(_ ours: MergeTree, _ theirs: MergeTree, base: MergeTree?) throws(MergeClash) -> MergeTree {
        guard case .array = ours else {
            if let base { return try ours.merging(with: theirs, from: base) }
            return try ours.merging(with: theirs)
        }
        var keys: [String: MergeTree] = [:]
        func object(_ tree: MergeTree) throws(MergeClash) -> MergeTree {
            guard case .array(let flat) = tree, flat.count.isMultiple(of: 2) else { throw MergeClash() }
            var object: [String: MergeTree] = [:]
            for index in stride(from: 0, to: flat.count, by: 2) {
                let text = flat[index].canonical
                keys[text] = flat[index]
                object[text] = flat[index + 1]
            }
            return .object(object)
        }
        let (mine, other) = (try object(ours), try object(theirs))
        let merged = if let base { try mine.merging(with: other, from: object(base)) } else { try mine.merging(with: other) }
        guard case .object(let entries) = merged else { return ours }
        return .array(entries.flatMap { [keys[$0.key]!, $0.value] })
    }
}
