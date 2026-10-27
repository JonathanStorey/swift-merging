/// Adds both sides' changes to the base, as a counter does, so two increments of one both count. A typed
/// strategy for any `Numeric` type. Needs a base, and a whole number that would overflow is a conflict.
///
/// ```swift
/// @Merged(.sum) var wins = 0
/// ```
public struct NumericSumMerge<Value: Numeric & Sendable>: MergeStrategy {
    public init() {}

    public func merge(base: Value, ours: Value, theirs: Value) throws(MergeConflict<Value>) -> Value {
        guard let whole = ours as? any FixedWidthInteger else { return ours + theirs - base }
        guard let sum = checkedSum(whole, theirs, base) as? Value else {
            throw MergeConflict(base: base, ours: ours, theirs: theirs)
        }
        return sum
    }
}

/// `ours + theirs - base`, or nil if a step overflows.
private func checkedSum<Whole: FixedWidthInteger>(_ ours: Whole, _ theirs: Any, _ base: Any) -> Any? {
    guard let theirs = theirs as? Whole, let base = base as? Whole else { return nil }
    let (added, overflowed) = ours.addingReportingOverflow(theirs)
    let (sum, underflowed) = added.subtractingReportingOverflow(base)
    return overflowed || underflowed ? nil : sum
}

// One shorthand per standard number type, as Foundation does for `.number`, since a static property
// can't be generic. Another number type writes `NumericSumMerge()`.
extension MergeStrategy where Self == NumericSumMerge<Int> { public static var sum: Self { Self() } }
extension MergeStrategy where Self == NumericSumMerge<Int8> { public static var sum: Self { Self() } }
extension MergeStrategy where Self == NumericSumMerge<Int16> { public static var sum: Self { Self() } }
extension MergeStrategy where Self == NumericSumMerge<Int32> { public static var sum: Self { Self() } }
extension MergeStrategy where Self == NumericSumMerge<Int64> { public static var sum: Self { Self() } }
extension MergeStrategy where Self == NumericSumMerge<UInt> { public static var sum: Self { Self() } }
extension MergeStrategy where Self == NumericSumMerge<UInt8> { public static var sum: Self { Self() } }
extension MergeStrategy where Self == NumericSumMerge<UInt16> { public static var sum: Self { Self() } }
extension MergeStrategy where Self == NumericSumMerge<UInt32> { public static var sum: Self { Self() } }
extension MergeStrategy where Self == NumericSumMerge<UInt64> { public static var sum: Self { Self() } }
extension MergeStrategy where Self == NumericSumMerge<Double> { public static var sum: Self { Self() } }
extension MergeStrategy where Self == NumericSumMerge<Float> { public static var sum: Self { Self() } }
