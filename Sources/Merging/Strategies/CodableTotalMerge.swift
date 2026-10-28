/// Merges a `Codable` value node by node like `CodableNodeMerge`, but never throws: every change that doesn't
/// clash still applies, from both sides, and a value both sides changed differently takes `Side`, as
/// `git merge -X theirs` does. A result that doesn't decode keeps that whole side.
///
/// ```swift
/// let merged = oursIsNewer
///     ? CodableTotalMerge<Note, OursSide>().merge(base: base, ours: mine, theirs: yours)
///     : CodableTotalMerge<Note, TheirsSide>().merge(base: base, ours: mine, theirs: yours)
/// ```
public struct CodableTotalMerge<Value: Codable & Sendable, Side: SideMarker>: MergeStrategy {
    public init() {}

    public func merge(base: Value, ours: Value, theirs: Value) -> Value {
        do {
            let encoder = TreeEncoder()
            let merged = try encoder.encode(ours).merging(with: encoder.encode(theirs), from: encoder.encode(base), favoring: Side.side)
            return try TreeDecoder().decode(Value.self, from: merged)
        } catch {
            return Side.side == .ours ? ours : theirs
        }
    }

    public func merge(ours: Value, theirs: Value) -> Value {
        do {
            let encoder = TreeEncoder()
            let merged = try encoder.encode(ours).merging(with: encoder.encode(theirs), favoring: Side.side)
            return try TreeDecoder().decode(Value.self, from: merged)
        } catch {
            return Side.side == .ours ? ours : theirs
        }
    }
}

/// The shortcut for `CodableTotalMerge`, as `.total(favoring: .ours)` or `.total(favoring: .theirs)`.
public struct TotalShortcut<Side: SideMarker>: MergeStrategy, MergeShortcut {
    public typealias Value = Never

    public init() {}

    public func merge(base: Never, ours: Never, theirs: Never) -> Never {}

    static func rule<Value: Codable & Sendable>(for type: Value.Type) -> MergeRule {
        MergeRule(type) { ours, theirs, base in
            let strategy = CodableTotalMerge<Value, Side>()
            guard let base else { return strategy.merge(ours: ours, theirs: theirs) }
            return strategy.merge(base: base, ours: ours, theirs: theirs)
        }
    }
}
extension MergeStrategy where Self == TotalShortcut<OursSide> {
    /// Merges node by node, and where both sides changed a value differently, keeps ours. Never a conflict.
    public static func total(favoring side: OursSide) -> Self { Self() }
}

extension MergeStrategy where Self == TotalShortcut<TheirsSide> {
    /// Merges node by node, and where both sides changed a value differently, keeps theirs. Never a conflict.
    public static func total(favoring side: TheirsSide) -> Self { Self() }
}

extension Merged {
    public init<Side>(wrappedValue: Value, _ strategy: TotalShortcut<Side>) where Strategy == TotalShortcut<Side> {
        self.init(wrappedValue: wrappedValue, shortcut: strategy)
    }
}
