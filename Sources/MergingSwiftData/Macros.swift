#if canImport(SwiftData)
import SwiftData

/// Makes a SwiftData `@Model` class merge property by property, by writing its `MergeableModel`
/// conformance. Every stored property merges: one marked `@Merge(.strategy)` by that strategy when both
/// sides changed it, and the rest by keeping the side that changed it. `@Transient` properties are left out.
///
/// A `@Relationship` merges by which objects it holds. A to-many one is a set, since SwiftData doesn't keep
/// its order: by default both sides' additions stay and either side's removals stick (`.byMembership`), and
/// `@Merge(.union)` keeps everything either side had. A to-one relationship keeps the side that changed it,
/// or takes `@Merge(.keep(.theirs))`. An object the other side deleted drops out.
///
/// ```swift
/// @Model @MergeableModel
/// final class Note {
///     @Merge(.byWord) var body = ""
///     @Merge(.sum) var likes = 0
///     @Merge(.keep(.theirs)) @Attribute(.externalStorage) var photo: Data?
///     var color = "red"
///     @Relationship var tags: [Tag] = []
/// }
/// ```
///
/// A property's type is taken from its annotation, or from a string, number, or `true`/`false` literal.
@attached(extension, conformances: MergeableModel,
          names: named(MergeSnapshot), named(mergeSnapshot), named(applyMergeSnapshot), named(mergeKeyPaths), named(mergeSnapshots))
public macro MergeableModel() = #externalMacro(module: "MergingMacros", type: "MergeableModelMacro")

/// Picks how a stored property of a `@MergeableModel` class merges when both sides changed it, with the same
/// strategies `@Merged` takes for a `Codable` value. It's only for SwiftData models.
///
/// ```swift
/// @Merge(.maximum) var highScore = 0
/// ```
@attached(peer)
public macro Merge<Strategy: MergeStrategy>(_ strategy: Strategy) = #externalMacro(module: "MergingMacros", type: "MergeMacro")
#endif
