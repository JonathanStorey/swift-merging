/// A type whose values merge. Implement `merging(_:base:)`, which merges `theirs` into this value, which is
/// ours, using their common ancestor when it's known. Throwing a `MergeConflict` is the only way to say two
/// versions can't be merged. The rest, `merge(_:base:)` and the static merges, are built on it.
///
/// `@Mergeable` writes it for a struct, merging it property by property:
///
/// ```swift
/// @Mergeable
/// struct Note {
///     var title = ""                                  // keeps the side that changed
///     @Merged(MaxMerge<Int>()) var highScore = 0
/// }
/// ```
///
/// To merge the whole value your own way, leave off `@Mergeable` and conform by hand. The two don't mix:
/// a `@Mergeable` struct that declares its own merge is an error.
public protocol Mergeable: Sendable {
    func merging(_ theirs: Self, base: Self?) throws(MergeConflict<Self>) -> Self
}

extension Mergeable {
    /// This value, which is ours, merged with `theirs` when there's no common ancestor.
    public func merging(_ theirs: Self) throws(MergeConflict<Self>) -> Self {
        try merging(theirs, base: nil)
    }

    /// Merges `theirs` into this value, which is ours. On a conflict the value is left unchanged.
    public mutating func merge(_ theirs: Self, base: Self? = nil) throws(MergeConflict<Self>) {
        self = try merging(theirs, base: base)
    }

    public static func merge(ours: Self, theirs: Self) throws(MergeConflict<Self>) -> Self {
        try ours.merging(theirs, base: nil)
    }

    public static func merge(base: Self, ours: Self, theirs: Self) throws(MergeConflict<Self>) -> Self {
        try ours.merging(theirs, base: base)
    }
}

/// Makes a struct `Mergeable` by merging each stored `var`: with its `@Merged` strategy, else its type's
/// own `Mergeable` merge, else, for an `Equatable` type, by keeping the side that changed. A property
/// that can't merge makes the whole value a conflict. `let` properties keep `ours`. To merge the whole
/// value another way, conform to `Mergeable` by hand instead.
@attached(extension, conformances: Mergeable, names: named(merging))
public macro Mergeable() = #externalMacro(module: "MergingMacros", type: "MergeableMacro")

/// Picks the strategy one stored property of a `@Mergeable` type merges with.
///
/// ```swift
/// @Merged(MaxMerge()) var highScore = 0
/// ```
@attached(peer)
public macro Merged<Strategy: MergeStrategy>(_ strategy: Strategy) = #externalMacro(module: "MergingMacros", type: "MergedMacro")
