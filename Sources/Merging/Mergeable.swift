/// A type whose values merge. Implement `merging(_:base:)`, which merges `theirs` into this value, which is
/// ours, knowing their common ancestor. Throwing a `MergeConflict` is the only way to say two versions can't
/// be merged.
///
/// Without an ancestor there's no telling which side changed, so `merging(_:)` throws a conflict unless the
/// type knows how to merge without one. The mutating `merge` and the static merges are built on these.
///
/// A `Codable` type gets both by conforming, and merges its encoded form property by property. `@Merged`
/// picks how one property merges. To merge the whole value your own way, write `merging(_:base:)`.
public protocol Mergeable: Sendable {
    func merging(_ theirs: Self, base: Self) throws(MergeConflict<Self>) -> Self
    func merging(_ theirs: Self) throws(MergeConflict<Self>) -> Self
}

extension Mergeable {
    public func merging(_ theirs: Self) throws(MergeConflict<Self>) -> Self {
        throw MergeConflict(ours: self, theirs: theirs)
    }

    /// Merges `theirs` into this value, which is ours. On a conflict the value is left unchanged.
    public mutating func merge(_ theirs: Self) throws(MergeConflict<Self>) {
        self = try merging(theirs)
    }

    /// Merges `theirs` into this value, which is ours, knowing their common ancestor. On a conflict the
    /// value is left unchanged.
    public mutating func merge(_ theirs: Self, base: Self) throws(MergeConflict<Self>) {
        self = try merging(theirs, base: base)
    }

    public static func merge(ours: Self, theirs: Self) throws(MergeConflict<Self>) -> Self {
        try ours.merging(theirs)
    }

    public static func merge(base: Self, ours: Self, theirs: Self) throws(MergeConflict<Self>) -> Self {
        try ours.merging(theirs, base: base)
    }
}
