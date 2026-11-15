/// A type that merges with another version of itself. Implement the two `merging` functions, and the
/// mutating `merge` functions and the static ones come with them.
///
/// ```swift
/// let merged = try ours.merging(with: theirs, from: base, favoring: .theirs)
/// try ours.merge(with: theirs, favoring: .ours)
/// let merged = try Note.merge(base: base, ours: ours, theirs: theirs, favoring: .ours)
/// ```
///
/// A merge always merges: where both sides changed the same thing, the favored side wins, as
/// `CodableTotalMerge` does. It throws only for versions that can't belong together. A type whose base is
/// itself merges with `@Merged(.mergeable(favoring:))`.
public protocol Mergeable {
    /// What a three-way merge starts from: the type itself, unless its versions are changes to something else.
    associatedtype MergeBase = Self

    /// This version merged with `theirs`, without a common ancestor.
    func merging(with theirs: Self, favoring side: MergeSide) throws -> Self

    /// This version merged with `theirs`, knowing their common ancestor.
    func merging(with theirs: Self, from base: MergeBase, favoring side: MergeSide) throws -> Self
}

extension Mergeable {
    /// Merges `theirs` into this version, without a common ancestor.
    public mutating func merge(with theirs: Self, favoring side: MergeSide) throws {
        self = try merging(with: theirs, favoring: side)
    }

    /// Merges `theirs` into this version, knowing their common ancestor.
    public mutating func merge(with theirs: Self, from base: MergeBase, favoring side: MergeSide) throws {
        self = try merging(with: theirs, from: base, favoring: side)
    }

    /// `ours` merged with `theirs`, without a common ancestor.
    public static func merge(ours: Self, theirs: Self, favoring side: MergeSide) throws -> Self {
        try ours.merging(with: theirs, favoring: side)
    }

    /// `ours` merged with `theirs`, knowing their common ancestor.
    public static func merge(base: MergeBase, ours: Self, theirs: Self, favoring side: MergeSide) throws -> Self {
        try ours.merging(with: theirs, from: base, favoring: side)
    }
}
