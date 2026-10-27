/// Adds both sides' changes to the base, as a counter does, so two increments of one both count. A typed
/// strategy for any `Numeric` type. Needs a base, and a whole number that would overflow is a conflict.
///
/// ```swift
/// @Merged(.sum) var wins = 0
/// ```
public struct NumericSumMerge<Value: Numeric & Sendable>: MergeStrategy {
    public init() {}

    public func merge(base: Value, ours: Value, theirs: Value) throws(MergeConflict<Value>) -> Value {
        guard let sum = summed(base: base, ours: ours, theirs: theirs) else { throw MergeConflict(base: base, ours: ours, theirs: theirs) }
        return sum
    }
}

/// `ours + theirs - base`, or nil if a whole number overflows.
func summed<Value: Numeric>(base: Value, ours: Value, theirs: Value) -> Value? {
    guard let whole = ours as? any FixedWidthInteger else { return ours + theirs - base }
    return checkedSum(whole, theirs, base) as? Value
}

private func checkedSum<Whole: FixedWidthInteger>(_ ours: Whole, _ theirs: Any, _ base: Any) -> Any? {
    guard let theirs = theirs as? Whole, let base = base as? Whole else { return nil }
    let (added, overflowed) = ours.addingReportingOverflow(theirs)
    let (sum, underflowed) = added.subtractingReportingOverflow(base)
    return overflowed || underflowed ? nil : sum
}

/// The shortcut for `NumericSumMerge`, as `.sum`.
public struct SumShortcut: MergeStrategy, MergeShortcut {
    public typealias Value = Never

    public init() {}

    public func merge(base: Never, ours: Never, theirs: Never) -> Never {}

    static func rule<Value: Codable & Sendable>(for type: Value.Type) -> MergeRule {
        MergeRule(type) { ours, theirs, base in
            guard let ours = ours as? any Numeric, let merged = try open(ours, theirs, base) as? Value else {
                throw ShortcutMismatch()
            }
            return merged
        }
    }

    private static func open<Opened: Numeric>(_ ours: Opened, _ theirs: Any, _ base: Any?) throws -> Opened {
        guard case let (theirs, base?) = try opened(ours, theirs, base), let sum = summed(base: base, ours: ours, theirs: theirs) else {
            throw ShortcutMismatch()
        }
        return sum
    }
}

extension MergeStrategy where Self == SumShortcut {
    /// A counter: both sides' increments count. Needs a base.
    public static var sum: SumShortcut { SumShortcut() }
}

extension Merged where Strategy == SumShortcut {
    public init(wrappedValue: Value, _ strategy: SumShortcut) where Value: Numeric {
        self.init(wrappedValue: wrappedValue, shortcut: strategy)
    }
}
