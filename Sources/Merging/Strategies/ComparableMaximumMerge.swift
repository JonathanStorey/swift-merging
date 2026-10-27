/// Keeps the larger value, by the type's own `<`. Merges with or without a base.
///
/// ```swift
/// @Merged(.maximum) var highScore = 0
/// @Merged(.maximum) var level = Level(number: 1)      // uses Level's own <
/// ```
public struct ComparableMaximumMerge<Value: Comparable & Sendable>: MergeStrategy {
    public init() {}

    public func merge(base: Value, ours: Value, theirs: Value) -> Value { merge(ours: ours, theirs: theirs) }

    public func merge(ours: Value, theirs: Value) -> Value { ours < theirs ? theirs : ours }
}

/// The shortcut for `ComparableMaximumMerge`, as `.maximum`.
public struct MaximumShortcut: MergeStrategy, MergeShortcut {
    public typealias Value = Never

    public init() {}

    public func merge(base: Never, ours: Never, theirs: Never) -> Never {}

    static func rule<Value: Codable & Sendable>(for type: Value.Type) -> MergeRule {
        MergeRule(type) { ours, theirs, base in
            guard let ours = ours as? any Comparable, let merged = try open(ours, theirs, base) as? Value else {
                throw ShortcutMismatch()
            }
            return merged
        }
    }

    private static func open<Opened: Comparable>(_ ours: Opened, _ theirs: Any, _ base: Any?) throws -> Opened {
        let (theirs, _) = try opened(ours, theirs, base)
        return ours < theirs ? theirs : ours
    }
}

// Named `maximum`, not `max`, since a static `max` would hide `Swift.max` inside every strategy.
extension MergeStrategy where Self == MaximumShortcut {
    /// Keeps the larger value: a high score, the furthest progress, the latest date.
    public static var maximum: MaximumShortcut { MaximumShortcut() }
}

extension Merged where Strategy == MaximumShortcut {
    public init(wrappedValue: Value, _ strategy: MaximumShortcut) where Value: Comparable {
        self.init(wrappedValue: wrappedValue, shortcut: strategy)
    }
}
