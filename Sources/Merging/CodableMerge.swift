/// A `Codable` type merges by conforming to `Mergeable`, node by node with `CodableNodeMerge`.
///
/// ```swift
/// struct Settings: Codable, Mergeable {
///     var theme = "light"
///     var favorites: [String] = []
/// }
/// ```
extension Mergeable where Self: Codable {
    public func merging(with theirs: Self, from base: Self) -> Self? {
        CodableNodeMerge().merge(base: base, ours: self, theirs: theirs)
    }

    public func merging(with theirs: Self) -> Self? {
        CodableNodeMerge().merge(ours: self, theirs: theirs)
    }
}
