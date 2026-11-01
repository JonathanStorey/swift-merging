/// A type whose values merge. Implement `merging(with:from:)`, which merges `theirs` into this value, which is
/// ours, knowing their common ancestor, and returns `nil` when the versions can't be merged.
///
/// Without an ancestor there's no telling which side changed, so `merging(with:)` returns `nil` unless the
/// type knows how to merge without one. The mutating `merge` and the static merges are built on these.
///
/// A `Codable` type gets both by conforming, and merges its encoded form property by property. `@Merged`
/// picks how one property merges. To merge the whole value your own way, write `merging(with:from:)`.
public protocol Mergeable: Sendable {
    func merging(with theirs: Self, from base: Self) -> Self?
    func merging(with theirs: Self) -> Self?
}

extension Mergeable {
    public func merging(with theirs: Self) -> Self? { nil }

    /// Merges `theirs` into this value, which is ours, and returns whether it could. If it couldn't, the
    /// value is left unchanged.
    @discardableResult
    public mutating func merge(with theirs: Self) -> Bool {
        guard let merged = merging(with: theirs) else { return false }
        self = merged
        return true
    }

    /// Merges `theirs` into this value, which is ours, knowing their common ancestor, and returns whether it
    /// could. If it couldn't, the value is left unchanged.
    @discardableResult
    public mutating func merge(with theirs: Self, from base: Self) -> Bool {
        guard let merged = merging(with: theirs, from: base) else { return false }
        self = merged
        return true
    }

    public static func merge(ours: Self, theirs: Self) -> Self? {
        ours.merging(with: theirs)
    }

    public static func merge(base: Self, ours: Self, theirs: Self) -> Self? {
        ours.merging(with: theirs, from: base)
    }
}
