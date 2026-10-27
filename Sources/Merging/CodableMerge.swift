/// A `Codable` type merges by conforming to `Mergeable`, node by node with `CodableNodeMerge`.
///
/// ```swift
/// struct Settings: Codable, Mergeable {
///     var theme = "light"
///     var favorites: [String] = []
/// }
/// ```
extension Mergeable where Self: Codable {
    public func merging(_ theirs: Self, base: Self) throws(MergeConflict<Self>) -> Self {
        try CodableNodeMerge().merge(base: base, ours: self, theirs: theirs)
    }

    public func merging(_ theirs: Self) throws(MergeConflict<Self>) -> Self {
        try CodableNodeMerge().merge(ours: self, theirs: theirs)
    }
}
