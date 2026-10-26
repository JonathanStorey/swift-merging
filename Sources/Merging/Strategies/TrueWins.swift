extension MergeKind {
    /// `true` if either side is, with or without a base.
    public enum TrueWins: StandardMerging {
        static func merge<Value: Codable & Sendable>(base: Value?, ours: Value, theirs: Value) throws -> Value {
            ((ours as! Bool) || (theirs as! Bool)) as! Value
        }
    }
}

extension StandardMerge where Value == Bool, Kind == MergeKind.TrueWins {
    /// A flag anyone can set, such as "flagged" or "read".
    public static var trueWins: Self { .init() }
}
