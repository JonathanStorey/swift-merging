/// Merges a set by what each side added and removed: an element is kept if either side added it, and
/// removed if either side removed it. Without a base, only equal sets merge.
///
/// ```swift
/// @Merged(.byMembership) var tags: Set<String> = []
/// @Merged(.byMembership) var shipping: Shipping = []     // an OptionSet
/// ```
public struct SetAlgebraMembershipMerge<Value: SetAlgebra & Sendable>: MergeStrategy {
    public init() {}

    public func merge(base: Value, ours: Value, theirs: Value) -> Value {
        .mergedByMembership(base: base, ours: ours, theirs: theirs)
    }

    public func merge(ours: Value, theirs: Value) throws(MergeConflict<Value>) -> Value {
        guard ours == theirs else { throw MergeConflict(ours: ours, theirs: theirs) }
        return ours
    }
}

/// The shortcut for `SetAlgebraMembershipMerge`, as `.byMembership`.
public struct ByMembershipShortcut: MergeStrategy, MergeShortcut {
    public typealias Value = Never

    public init() {}

    public func merge(base: Never, ours: Never, theirs: Never) -> Never {}

    static func rule<Value: Codable & Sendable>(for type: Value.Type) -> MergeRule {
        MergeRule(type) { ours, theirs, base in
            guard let ours = ours as? any SetAlgebra, let merged = try open(ours, theirs, base) as? Value else {
                throw ShortcutMismatch()
            }
            return merged
        }
    }

    private static func open<Opened: SetAlgebra>(_ ours: Opened, _ theirs: Any, _ base: Any?) throws -> Opened {
        let (theirs, base) = try opened(ours, theirs, base)
        guard let base else {
            guard ours == theirs else { throw ShortcutMismatch() }
            return ours
        }
        return .mergedByMembership(base: base, ours: ours, theirs: theirs)
    }
}

extension MergeStrategy where Self == ByMembershipShortcut {
    /// Merges who's in a set, such as tags.
    public static var byMembership: ByMembershipShortcut { ByMembershipShortcut() }
}

extension Merged where Strategy == ByMembershipShortcut {
    public init(wrappedValue: Value, _ strategy: ByMembershipShortcut) where Value: SetAlgebra {
        self.init(wrappedValue: wrappedValue, shortcut: strategy)
    }
}

extension SetAlgebra {
    /// What both sides kept, plus what either added.
    static func mergedByMembership(base: Self, ours: Self, theirs: Self) -> Self {
        ours.intersection(theirs).union(ours.subtracting(base)).union(theirs.subtracting(base))
    }
}

/// Every set merges by membership, since it encodes in no particular order. This works on the merge tree,
/// matching elements by their canonical text.
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
