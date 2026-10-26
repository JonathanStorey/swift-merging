extension MergeKind {
    /// Keeps the larger value, by the type's own `<`, with or without a base.
    public enum Maximum: StandardMerging {
        static func merge<Value: Codable & Sendable>(base: Value?, ours: Value, theirs: Value) throws -> Value {
            guard let ours = ours as? any Comparable else { throw Unmergeable() }
            return larger(ours, theirs) as! Value
        }
    }
}

private func larger<T: Comparable>(_ ours: T, _ theirs: Any) -> T {
    max(ours, theirs as! T)
}

extension StandardMerge where Value: Comparable, Kind == MergeKind.Maximum {
    /// Keeps the larger value: a high score, the furthest progress.
    public static var max: Self { .init() }
}
