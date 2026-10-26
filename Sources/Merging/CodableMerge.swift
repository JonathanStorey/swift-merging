/// A `Codable` type merges by conforming to `Mergeable`, through a snapshot of its encoded form. Knowing
/// the common ancestor, a property only one side changed keeps that side. Where both changed it, a `@Merged`
/// property merges by its strategy, a `Mergeable` one by its type's own merge, an object key by key, an array
/// element by element, and anything else is a conflict. The result must decode, or the merge is a conflict.
///
/// Without an ancestor, only what's equal merges, along with properties whose strategy or type can merge
/// without one.
///
/// ```swift
/// struct Settings: Codable, Mergeable {
///     var theme = "light"
///     var favorites: [String] = []
/// }
/// ```
extension Mergeable where Self: Codable {
    public func merging(_ theirs: Self, base: Self) throws(MergeConflict<Self>) -> Self {
        do {
            let encoder = SnapshotEncoder()
            let merged = try encoder.encode(self).merging(encoder.encode(theirs), base: encoder.encode(base))
            return try SnapshotDecoder().decode(Self.self, from: merged)
        } catch {
            throw MergeConflict(base: base, ours: self, theirs: theirs)
        }
    }

    public func merging(_ theirs: Self) throws(MergeConflict<Self>) -> Self {
        do {
            let encoder = SnapshotEncoder()
            let merged = try encoder.encode(self).merging(encoder.encode(theirs))
            return try SnapshotDecoder().decode(Self.self, from: merged)
        } catch {
            throw MergeConflict(ours: self, theirs: theirs)
        }
    }
}
