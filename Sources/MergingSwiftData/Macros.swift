#if canImport(SwiftData)
import SwiftData

/// Makes a SwiftData `@Model` class merge property by property, by writing its `MergeableModel`
/// conformance. Merging is opt-in: a property marked `@Merge(.strategy)` merges by that strategy when both
/// sides changed it, and every other stored property does exactly what SwiftData would without this
/// library. `@Transient` properties are left out.
///
/// A `@Relationship` merges only with `@Merge` too. A to-many one is a set of related objects, since
/// SwiftData doesn't keep its order, so `.byMembership` keeps both sides' additions and either side's
/// removals, and `.union` keeps everything either side had. An object the other side deleted drops out.
///
/// ```swift
/// @Model @MergeableModel
/// final class Note {
///     @Merge(.byWord) var body = ""
///     @Merge(.sum) var likes = 0
///     @Merge(.keep(.theirs)) @Attribute(.externalStorage) var photo: Data?
///     @Merge(.byMembership) @Relationship var tags: [Tag] = []
///     var color = "red"
/// }
/// ```
///
/// A property's type is taken from its annotation, or from a string, number, or `true`/`false` literal.
@attached(extension, conformances: MergeableModel,
          names: named(MergeSnapshot), named(mergeSnapshot), named(applyMergeSnapshot), named(mergeKeyPaths),
          named(mergeStrategyProperties), named(mergeSnapshots))
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
