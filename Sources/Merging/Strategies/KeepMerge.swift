/// A side of a merge, which `.keep` and `.byNode(favoring:)` name with `OursSide` and `TheirsSide`.
public enum MergeSide: Sendable {
    case ours
    case theirs
}

/// Always keeps ours when both sides changed the value. Merges with or without a base.
///
/// ```swift
/// @Merged(.keep(.ours)) var draft = ""
/// ```
public struct KeepOursMerge<Value: Sendable>: MergeStrategy {
    public init() {}

    public func merge(base: Value, ours: Value, theirs: Value) -> Value { ours }

    public func merge(ours: Value, theirs: Value) -> Value { ours }
}

/// Always keeps theirs when both sides changed the value. Merges with or without a base.
///
/// ```swift
/// @Merged(.keep(.theirs)) var cachedTotal = 0
/// ```
public struct KeepTheirsMerge<Value: Sendable>: MergeStrategy {
    public init() {}

    public func merge(base: Value, ours: Value, theirs: Value) -> Value { theirs }

    public func merge(ours: Value, theirs: Value) -> Value { theirs }
}

/// A side as a type, `.ours` or `.theirs`, so `@Merged` rebuilds a strategy that names one when a value
/// decodes.
public protocol SideMarker: Sendable {
    static var side: MergeSide { get }
}

/// The `.ours` in `.keep(.ours)` and `.byNode(favoring: .ours)`.
public struct OursSide: SideMarker {
    public static var side: MergeSide { .ours }
    public static var ours: OursSide { OursSide() }
}

/// The `.theirs` in `.keep(.theirs)` and `.byNode(favoring: .theirs)`.
public struct TheirsSide: SideMarker {
    public static var side: MergeSide { .theirs }
    public static var theirs: TheirsSide { TheirsSide() }
}

/// The shortcut for `KeepOursMerge` and `KeepTheirsMerge`, as `.keep(.ours)` and `.keep(.theirs)`.
public struct KeepShortcut<Side: SideMarker>: MergeStrategy, MergeShortcut {
    public typealias Value = Never

    public init() {}

    public func merge(base: Never, ours: Never, theirs: Never) -> Never {}

    static func rule<Value: Codable & Sendable>(for type: Value.Type) -> MergeRule {
        MergeRule(type) { ours, theirs, _ in Side.side == .ours ? ours : theirs }
    }
}

extension MergeStrategy where Self == KeepShortcut<OursSide> {
    /// Keeps ours when both sides changed the value: a draft only this device should finish.
    public static func keep(_ side: OursSide) -> Self { Self() }
}

extension MergeStrategy where Self == KeepShortcut<TheirsSide> {
    /// Keeps theirs when both sides changed the value: a cached or derived value the other side recomputed.
    public static func keep(_ side: TheirsSide) -> Self { Self() }
}

extension Merged {
    public init<Side>(wrappedValue: Value, _ strategy: KeepShortcut<Side>) where Strategy == KeepShortcut<Side> {
        self.init(wrappedValue: wrappedValue, shortcut: strategy)
    }
}
