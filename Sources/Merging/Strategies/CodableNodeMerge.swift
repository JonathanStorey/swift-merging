/// Merges a `Codable` value node by node through its `CodableTree`, a structured merge: a node only one
/// side changed keeps that side. Where both changed it, a `@Merged` property merges by its strategy, a
/// `Mergeable` one by its type's own merge, an object key by key, an array element by element, and anything
/// else is a conflict. The result must decode, or the merge is a conflict. Without a base, only what's
/// equal merges, along with nodes whose strategy or type can merge without one.
///
/// It's how a `Codable` type merges when it conforms to `Mergeable` with no code, and it merges any other
/// `Codable` value too:
///
/// ```swift
/// try CodableNodeMerge<Address>().merge(base: original, ours: mine, theirs: yours)
/// ```
///
/// With `favoring`, it never throws. Every change that doesn't clash still applies, from both sides, and
/// only a value both sides changed differently takes the favored side, as `git merge -X theirs` does. That
/// suits a sync engine that knows which side is newer:
///
/// ```swift
/// try CodableNodeMerge<Note>(favoring: oursIsNewer ? .ours : .theirs).merge(base: base, ours: mine, theirs: yours)
/// ```
public struct CodableNodeMerge<Value: Codable & Sendable>: MergeStrategy {
    /// The side a clash keeps, or `nil` to throw a conflict. A result that doesn't decode keeps that whole
    /// side. `@Merged` makes the strategy with `init()`, so this is for calling it directly.
    public var favoring: MergeSide?

    public init() {}

    public init(favoring: MergeSide?) {
        self.favoring = favoring
    }

    public func merge(base: Value, ours: Value, theirs: Value) throws(MergeConflict<Value>) -> Value {
        do {
            let encoder = TreeEncoder()
            let merged = try encoder.encode(ours).merging(with: encoder.encode(theirs), from: encoder.encode(base), favoring: favoring)
            return try TreeDecoder().decode(Value.self, from: merged)
        } catch {
            if let favoring { return favoring == .ours ? ours : theirs }
            throw MergeConflict(base: base, ours: ours, theirs: theirs)
        }
    }

    public func merge(ours: Value, theirs: Value) throws(MergeConflict<Value>) -> Value {
        do {
            let encoder = TreeEncoder()
            let merged = try encoder.encode(ours).merging(with: encoder.encode(theirs), favoring: favoring)
            return try TreeDecoder().decode(Value.self, from: merged)
        } catch {
            if let favoring { return favoring == .ours ? ours : theirs }
            throw MergeConflict(ours: ours, theirs: theirs)
        }
    }
}

/// The shortcut for `CodableNodeMerge`, as `.byNode`.
public struct ByNodeShortcut: MergeStrategy, MergeShortcut {
    public typealias Value = Never

    public init() {}

    public func merge(base: Never, ours: Never, theirs: Never) -> Never {}

    static func rule<Value: Codable & Sendable>(for type: Value.Type) -> MergeRule {
        MergeRule(type) { ours, theirs, base in
            let strategy = CodableNodeMerge<Value>()
            guard let base else { return try strategy.merge(ours: ours, theirs: theirs) }
            return try strategy.merge(base: base, ours: ours, theirs: theirs)
        }
    }
}

extension MergeStrategy where Self == ByNodeShortcut {
    /// Merges node by node, as a `Codable` `Mergeable` type does, overriding a type's own merge.
    public static var byNode: ByNodeShortcut { ByNodeShortcut() }
}

extension Merged where Strategy == ByNodeShortcut {
    public init(wrappedValue: Value, _ strategy: ByNodeShortcut) {
        self.init(wrappedValue: wrappedValue, shortcut: strategy)
    }
}

/// The shortcut for `CodableNodeMerge(favoring:)`, as `.byNode(favoring: .ours)` or `.byNode(favoring: .theirs)`.
/// It never throws: what doesn't clash merges node by node, and a clash takes the favored side.
public struct ByNodeFavoringShortcut<Side: SideMarker>: MergeStrategy, MergeShortcut {
    public typealias Value = Never

    public init() {}

    public func merge(base: Never, ours: Never, theirs: Never) -> Never {}

    static func rule<Value: Codable & Sendable>(for type: Value.Type) -> MergeRule {
        MergeRule(type) { ours, theirs, base in
            let strategy = CodableNodeMerge<Value>(favoring: Side.side)
            guard let base else { return try strategy.merge(ours: ours, theirs: theirs) }
            return try strategy.merge(base: base, ours: ours, theirs: theirs)
        }
    }
}

extension MergeStrategy where Self == ByNodeFavoringShortcut<OursSide> {
    /// Merges node by node, and where both sides changed a value differently, keeps ours. Never a conflict.
    public static func byNode(favoring side: OursSide) -> Self { Self() }
}

extension MergeStrategy where Self == ByNodeFavoringShortcut<TheirsSide> {
    /// Merges node by node, and where both sides changed a value differently, keeps theirs. Never a conflict.
    public static func byNode(favoring side: TheirsSide) -> Self { Self() }
}

extension Merged {
    public init<Side>(wrappedValue: Value, _ strategy: ByNodeFavoringShortcut<Side>) where Strategy == ByNodeFavoringShortcut<Side> {
        self.init(wrappedValue: wrappedValue, shortcut: strategy)
    }
}
