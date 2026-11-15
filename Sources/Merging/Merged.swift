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
    /// `RangeReplaceableCollectionElementMerge`: a list element by element, or text character by character.
    case byElement
    /// `DictionaryKeyedMerge`: a dictionary key by key.
    case byKey
    /// `SetAlgebraMembershipMerge`: a set by what each side added and removed.
    case byMembership
    /// `StringWordMerge`: text word by word.
    case byWord
    /// `KeepMerge`: keeps the named side when both changed the value.
    case keep(MergeSide)
    /// `ComparableMaximumMerge`: the larger value.
    case maximum
    /// `NumericSumMerge`: a counter, so both sides' changes count.
    case sum
    /// `BoolTrueWinsMerge`: `true` if either side is.
    case trueWins
    /// `SetAlgebraUnionMerge`: a set that keeps every addition, with or without a base.
    case union
}
