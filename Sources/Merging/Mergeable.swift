/// A type whose values merge. Implement the two-way merge, and the three-way merge, which is called
/// whenever the common ancestor is known, uses it by default. Throwing a `MergeConflict` is the only way
/// to say two versions can't be merged.
///
/// `@Mergeable` writes both for a struct, merging it property by property:
///
/// ```swift
/// @Mergeable
/// struct Note {
///     var title = ""                                  // keeps the side that changed
///     @Merged(MaxMerge()) var highScore = 0
/// }
/// ```
///
/// Write your own `merge` to decide differently. The macro still adds `mergeProperties(base:ours:theirs:)`,
/// so yours can merge property by property and settle only what that couldn't.
public protocol Mergeable: Sendable {
    static func merge(ours: Self, theirs: Self) throws(MergeConflict<Self>) -> Self
    static func merge(base: Self, ours: Self, theirs: Self) throws(MergeConflict<Self>) -> Self
}

extension Mergeable {
    public static func merge(base: Self, ours: Self, theirs: Self) throws(MergeConflict<Self>) -> Self {
        try merge(ours: ours, theirs: theirs)
    }
}

/// Makes a struct `Mergeable` by merging each stored `var`: with its `@Merged` strategy, else its type's
/// own `Mergeable` merge, else, for an `Equatable` type, by keeping the side that changed. A property
/// that can't merge makes the whole value a conflict. `let` properties keep `ours`.
@attached(extension, conformances: Mergeable, names: named(merge), named(mergeProperties))
public macro Mergeable() = #externalMacro(module: "MergingMacros", type: "MergeableMacro")

/// Picks the strategy one stored property of a `@Mergeable` type merges with.
///
/// ```swift
/// @Merged(MaxMerge()) var highScore = 0
/// ```
@attached(peer)
public macro Merged<Strategy: MergeStrategy>(_ strategy: Strategy) = #externalMacro(module: "MergingMacros", type: "MergedMacro")
