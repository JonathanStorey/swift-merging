/// A type whose values merge. Implement `merging(with:from:)`, which merges `theirs` into this value, which is
/// ours, knowing their common ancestor. Throwing a `MergeConflict` is the only way to say two versions can't
/// be merged.
///
/// Without an ancestor there's no telling which side changed, so `merging(with:)` throws a conflict unless the
/// type knows how to merge without one. The mutating `merge` and the static merges are built on these.
///
/// A `Codable` type gets both by conforming, and merges its encoded form property by property. `@Merged`
/// picks how one property merges. To merge the whole value your own way, write `merging(with:from:)`.
public protocol Mergeable: Sendable {
    func merging(with theirs: Self, from base: Self) throws(MergeConflict<Self>) -> Self
    func merging(with theirs: Self) throws(MergeConflict<Self>) -> Self
}

extension Mergeable {
    public func merging(with theirs: Self) throws(MergeConflict<Self>) -> Self {
        throw MergeConflict(ours: self, theirs: theirs)
    }

    /// Merges `theirs` into this value, which is ours. On a conflict the value is left unchanged.
    public mutating func merge(with theirs: Self) throws(MergeConflict<Self>) {
        self = try merging(with: theirs)
    }

    /// Merges `theirs` into this value, which is ours, knowing their common ancestor. On a conflict the
    /// value is left unchanged.
    public mutating func merge(with theirs: Self, from base: Self) throws(MergeConflict<Self>) {
        self = try merging(with: theirs, from: base)
    }

    public static func merge(ours: Self, theirs: Self) throws(MergeConflict<Self>) -> Self {
        try ours.merging(with: theirs)
    }

    public static func merge(base: Self, ours: Self, theirs: Self) throws(MergeConflict<Self>) -> Self {
        try ours.merging(with: theirs, from: base)
    }
}
