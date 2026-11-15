/// Picks how a property merges, and writes `$name`, a `MergedProperty` that merges it by that strategy. It
/// works the same on a struct, a class, or a SwiftData `@Model`, and leaves the property itself untouched.
///
/// ```swift
/// struct Player: Codable {
///     @Merged(.keep(.ours)) var nickname = ""          // a strategy of the package's own
///     @Merged(LongerMerge()) var title: String = ""     // a strategy of your own
/// }
///
/// player.$title.merging(with: theirs.title, from: base.title)
/// ```
///
/// The property's type comes from its annotation, or from a string, number, or `true`/`false` literal.
@attached(peer, names: prefixed(`$`))
public macro Merged<Strategy: MergeStrategy>(_ strategy: Strategy) = #externalMacro(module: "MergingMacros", type: "MergedMacro")

/// Picks one of the package's own strategies by its shorthand, such as `.keep(.ours)`.
@attached(peer, names: prefixed(`$`))
public macro Merged(_ strategy: MergeShorthand) = #externalMacro(module: "MergingMacros", type: "MergedMacro")

/// The shorthand `@Merged` takes for the package's own strategies. Most are generic over the property's
/// type, which an attribute can't see, so the macro writes each one out as its strategy for that type:
/// `.keep(.ours)` on a `String` becomes `KeepMerge<String>(.ours)`.
public enum MergeShorthand: Sendable {
    /// `KeepMerge`: keeps the named side when both changed the value.
    case keep(MergeSide)
}
