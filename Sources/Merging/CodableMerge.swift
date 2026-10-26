/// A `Codable` type that conforms to `Mergeable` without writing its own merge merges as a snapshot of its
/// encoded form. Knowing the common ancestor, objects merge key by key, arrays element by element, and
/// anything else keeps the side that changed. The result must decode, or the merge is a conflict. Without
/// an ancestor there's no telling which side changed, so the versions merge only if they're equal.
///
/// ```swift
/// struct Settings: Codable, Mergeable {
///     var theme = "light"
///     var favorites: [String] = []
/// }
/// ```
extension Mergeable where Self: Codable {
    public func merging(_ theirs: Self) throws(MergeConflict<Self>) -> Self {
        let encoder = SnapshotEncoder()
        guard let ours = try? encoder.encode(self), let other = try? encoder.encode(theirs), ours == other else {
            throw MergeConflict(ours: self, theirs: theirs)
        }
        return self
    }

    public func merging(_ theirs: Self, base: Self) throws(MergeConflict<Self>) -> Self {
        do {
            let encoder = SnapshotEncoder()
            let merged = try encoder.encode(self).merging(encoder.encode(theirs), base: encoder.encode(base))
            return try SnapshotDecoder().decode(Self.self, from: merged)
        } catch {
            throw MergeConflict(base: base, ours: self, theirs: theirs)
        }
    }
}
