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
/// With `onClash`, it never throws. Each clash keeps that side and the rest still merges, which suits a sync
/// engine that knows which side is newer:
///
/// ```swift
/// try CodableNodeMerge<Note>(onClash: oursIsNewer ? .ours : .theirs).merge(base: base, ours: mine, theirs: yours)
/// ```
public struct CodableNodeMerge<Value: Codable & Sendable>: MergeStrategy {
    /// The side a clash keeps, or `nil` to throw a conflict. A result that doesn't decode keeps that whole
    /// side. `@Merged` makes the strategy with `init()`, so this is for calling it directly.
    public var onClash: MergeSide?

    public init() {}

    public init(onClash: MergeSide?) {
        self.onClash = onClash
    }

    public func merge(base: Value, ours: Value, theirs: Value) throws(MergeConflict<Value>) -> Value {
        do {
            let encoder = TreeEncoder()
            let merged = try encoder.encode(ours).merging(with: encoder.encode(theirs), from: encoder.encode(base), onClash: onClash)
            return try TreeDecoder().decode(Value.self, from: merged)
        } catch {
            if let onClash { return onClash == .ours ? ours : theirs }
            throw MergeConflict(base: base, ours: ours, theirs: theirs)
        }
    }

    public func merge(ours: Value, theirs: Value) throws(MergeConflict<Value>) -> Value {
        do {
            let encoder = TreeEncoder()
            let merged = try encoder.encode(ours).merging(with: encoder.encode(theirs), onClash: onClash)
            return try TreeDecoder().decode(Value.self, from: merged)
        } catch {
            if let onClash { return onClash == .ours ? ours : theirs }
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
