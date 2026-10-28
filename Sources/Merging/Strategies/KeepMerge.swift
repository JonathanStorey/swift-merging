/// The side `CodableNodeMerge(favoring:)` keeps where both sides changed a value and nothing merged it.
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

/// The `.ours` in `.keep(.ours)`. The side is a type so `@Merged` rebuilds it when a value decodes.
public struct KeepOurs: Sendable {
    public static var ours: KeepOurs { KeepOurs() }
}

/// The `.theirs` in `.keep(.theirs)`.
public struct KeepTheirs: Sendable {
    public static var theirs: KeepTheirs { KeepTheirs() }
}

/// The shortcut for `KeepOursMerge`, as `.keep(.ours)`.
public struct KeepOursShortcut: MergeStrategy, MergeShortcut {
    public typealias Value = Never

    public init() {}

    public func merge(base: Never, ours: Never, theirs: Never) -> Never {}

    static func rule<Value: Codable & Sendable>(for type: Value.Type) -> MergeRule {
        MergeRule(type) { ours, _, _ in ours }
    }
}

/// The shortcut for `KeepTheirsMerge`, as `.keep(.theirs)`.
public struct KeepTheirsShortcut: MergeStrategy, MergeShortcut {
    public typealias Value = Never

    public init() {}

    public func merge(base: Never, ours: Never, theirs: Never) -> Never {}

    static func rule<Value: Codable & Sendable>(for type: Value.Type) -> MergeRule {
        MergeRule(type) { _, theirs, _ in theirs }
    }
}

extension MergeStrategy where Self == KeepOursShortcut {
    /// Keeps ours when both sides changed the value: a draft only this device should finish.
    public static func keep(_ side: KeepOurs) -> KeepOursShortcut { KeepOursShortcut() }
}

extension MergeStrategy where Self == KeepTheirsShortcut {
    /// Keeps theirs when both sides changed the value: a cached or derived value the other side recomputed.
    public static func keep(_ side: KeepTheirs) -> KeepTheirsShortcut { KeepTheirsShortcut() }
}

extension Merged where Strategy == KeepOursShortcut {
    public init(wrappedValue: Value, _ strategy: KeepOursShortcut) {
        self.init(wrappedValue: wrappedValue, shortcut: strategy)
    }
}

extension Merged where Strategy == KeepTheirsShortcut {
    public init(wrappedValue: Value, _ strategy: KeepTheirsShortcut) {
        self.init(wrappedValue: wrappedValue, shortcut: strategy)
    }
}
