extension MergeKind {
    /// Merges text word by word. Needs a base.
    public enum ByWord: StandardMerging {
        static func merge<Value: Codable & Sendable>(base: Value?, ours: Value, theirs: Value) throws -> Value {
            try Text.merge(base: base, ours: ours, theirs: theirs)
        }
    }
}

extension StandardMerge where Value == String, Kind == MergeKind.ByWord {
    /// Edits to different words combine.
    public static var byWord: Self { .init() }
}
