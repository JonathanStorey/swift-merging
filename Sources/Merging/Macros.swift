/// Picks the strategy one stored property merges with, instead of its type's `Mergeable` strategy or
/// `ThreeWayMerge`. It's a marker the merging code reads, and adds no code of its own.
///
/// ```swift
/// @Merged(MaxMerge()) var highScore = 0
/// ```
@attached(peer)
public macro Merged<Strategy: MergeStrategy>(_ strategy: Strategy) = #externalMacro(module: "MergingMacros", type: "MergedMacro")
