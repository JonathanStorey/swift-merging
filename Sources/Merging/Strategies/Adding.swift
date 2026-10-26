extension MergeKind {
    /// Adds both sides' changes to the base, as a counter does. Needs a base, and an integer that would
    /// overflow is a conflict.
    public enum Adding: StandardMerging {
        static func merge<Value: Codable & Sendable>(base: Value?, ours: Value, theirs: Value) throws -> Value {
            guard let base else { throw Unmergeable() }
            if let ours = ours as? any FixedWidthInteger { return try sum(ours, theirs, base) as! Value }
            guard let ours = ours as? any AdditiveArithmetic else { throw Unmergeable() }
            return sum(ours, theirs, base) as! Value
        }
    }
}

private func sum<T: FixedWidthInteger>(_ ours: T, _ theirs: Any, _ base: Any) throws -> T {
    let (added, overflowed) = ours.addingReportingOverflow(theirs as! T)
    let (result, underflowed) = added.subtractingReportingOverflow(base as! T)
    guard !overflowed, !underflowed else { throw Unmergeable() }
    return result
}

private func sum<T: AdditiveArithmetic>(_ ours: T, _ theirs: Any, _ base: Any) -> T {
    ours + (theirs as! T) - (base as! T)
}

extension StandardMerge where Value: AdditiveArithmetic, Kind == MergeKind.Adding {
    /// A counter: both sides' increments count. Needs a base.
    public static var adding: Self { .init() }
}
