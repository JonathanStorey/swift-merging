# Strategies

| Strategy | Type | Works with | Merges | Needs a base |
| --- | --- | --- | --- | --- |
| [`.byNode`](#bynode) | `CodableNodeMerge` | any `Codable` | node by node | yes |
| [`.byElement`](#byelement) | `RangeReplaceableCollectionElementMerge` | arrays, `String` | element by element | yes |
| [`.byKey`](#bykey) | `DictionaryKeyedMerge` | any `Dictionary` | key by key | yes |
| [`.byMembership`](#bymembership) | `SetAlgebraMembershipMerge` | `Set`, any `OptionSet` | additions and removals from both | yes |
| [`.byWord`](#byword) | `StringWordMerge` | `String` | word by word | yes |
| [`.keep(.ours)`, `.keep(.theirs)`](#keep) | `KeepMerge` | anything | the named side | no |
| [`.maximum`](#maximum) | `ComparableMaximumMerge` | any `Comparable` | the larger | no |
| [`.mergeable(favoring:)`](#mergeable) | `MergeableMerge` | any `Mergeable` | by its own `merging` | no |
| [`.sum`](#sum) | `NumericSumMerge` | any `Numeric` | both changes added | yes |
| [`.total(favoring:)`](#total) | `CodableTotalMerge` | any `Codable` | node by node, clashes to one side | no |
| [`.trueWins`](#truewins) | `BoolTrueWinsMerge` | `Bool` | `true` if either is | no |
| [`.union`](#union) | `SetAlgebraUnionMerge` | `Set`, any `OptionSet` | additions and removals from both | no |

A strategy decides only when both sides changed a property. A side only one changed keeps that side, which
needs the value to be `Equatable`. A strategy that **needs a base** only merges in a three-way merge.
Without a base, only equal values merge, and any difference is a conflict. A strategy that doesn't need one
merges any two versions. A conflict is `nil` from `merging` and `false` from `merge`.

## .byNode

`CodableNodeMerge` is a structured merge for any `Codable` value. It encodes the value into a tree, merges
the tree node by node, and decodes the result.

Where both sides changed a node:

- an object merges key by key;
- an array merges element by element, as `.byElement` does, with an element both sides changed merging
  node by node;
- a `Set` merges `.byMembership`;
- a `Dictionary` merges key by key, whatever its key type, with a value both sides changed merging node
  by node;
- a `String`, number or `Bool` changed differently on both sides is a conflict.

```swift
@Merged(.byNode) var address: Address = Address()
CodableNodeMerge<Address>().merge(base: original, ours: mine, theirs: yours)
```

Merging an `Address` with a `street` and a `city`:

| Base | Ours | Theirs | Result |
| --- | --- | --- | --- |
| {Elm, Oslo} | {Oak, Oslo} | {Elm, Bergen} | {Oak, Bergen} |
| {Elm, Oslo} | {Oak, Oslo} | {Pine, Oslo} | conflict |
| none | {Oak, Oslo} | {Elm, Oslo} | conflict |

- **Good for:** any `Codable` value, including types from other libraries.
- **Needs a base:** Yes. Without one, objects with the same keys merge key by key, and arrays of the same
  length element by element, so only equal values merge.
- **Conflicts:** wherever both sides changed a plain value differently, or when the merged result doesn't
  decode, such as one that breaks a type's own validation.
- It encodes and decodes on every merge, which fits syncing better than tight loops.

## .byElement

`RangeReplaceableCollectionElementMerge` merges a list element by element, like a three-way merge of
lines. An element either side removed is removed, and what each side inserted goes where it was inserted,
ours first. On a `String`, it merges character by character.

```swift
@Merged(.byElement) var steps: [String] = []
@Merged(.byElement) var code = ""
```

| Base | Ours | Theirs | Result |
| --- | --- | --- | --- |
| [boil, stir, serve] | [boil, salt, stir, serve] | [stir, serve, eat] | [salt, stir, serve, eat] |
| soup | soups | Soup | Soups |
| [a, b] | [a, x] | [a, y] | conflict |
| none | [a, b] | [a, b, c] | conflict |

- **Good for:** ordered lists where position matters and duplicates are allowed, such as steps, playlists
  and layers.
- **Needs a base:** Yes. Without one, only equal lists merge.
- **An element both sides changed:** elements match by `==`, so different replacements of the same element
  are a conflict. For a list of structs where two people edit different fields of the same item, use
  `.byNode`, which merges that element node by node.
- **Conflicts:** when both sides replaced the same element differently and the replacements can't merge,
  or without a base when the lengths differ. Different insertions at the same spot are both kept, ours
  first.
- **Watch for:** moves. A move is a removal plus an insertion, so two people moving the same element to
  different places keep both copies.
- On a `String` it merges character by character. `.byWord` is usually the better fit for prose.

## .byKey

`DictionaryKeyedMerge` merges a dictionary key by key, whatever the key's type. A key only one side added,
changed or removed keeps that side. A key both sides changed merges only if they changed it alike.

```swift
@Merged(.byKey) var pins: [Spot: String] = [:]
@Merged(.byKey) var scores: [String: Int] = [:]
```

| Base | Ours | Theirs | Result |
| --- | --- | --- | --- |
| [a: 1] | [a: 1, b: 2] | [:] | [b: 2] |
| [a: 1] | [a: 2] | [a: 3] | conflict |
| none | [a: 1] | [a: 1, b: 2] | conflict |

- **Good for:** settings by name, scores by player, any lookup table.
- **Needs a base:** Yes. Without one, only equal dictionaries merge, since there's no telling an added key
  from a removed one.
- **Conflicts:** when one side removed a key the other changed, or both changed a value differently. For
  values that are structs, use `.byNode`, which merges a value both sides changed node by node.
- Any `Hashable` key works, including structs. The values must be `Equatable`.

## .byMembership

`SetAlgebraMembershipMerge` merges by what each side added and removed: an element is kept if either side
added it, and removed if either side removed it.

```swift
@Merged(.byMembership) var tags: Set<String> = []
@Merged(.byMembership) var shipping: Shipping = []    // an OptionSet
```

| Base | Ours | Theirs | Result |
| --- | --- | --- | --- |
| {a, b, c} | {a, c, ours} | {a, b, theirs} | {a, ours, theirs} |
| none | {a, b} | {a, c} | conflict |

- **Good for:** tags, selected options, permissions, followers.
- **Needs a base:** Yes. Without one, only equal sets merge, since there's no telling an addition from a removal. Use
  `.union` to keep both sides instead.
- **Conflicts:** only without a base, when the sets differ.
- Every `Set` merges this way by default. The shorthand is what lets an `OptionSet` merge by membership.

## .byWord

`StringWordMerge` splits text into words, merges the word lists like lines in a three-way text merge, and
joins them back. Edits to different words combine. Edits to the same word conflict.

```swift
@Merged(.byWord) var note = ""
```

| Base | Ours | Theirs | Result |
| --- | --- | --- | --- |
| the quick brown fox | the slow brown fox | the quick brown cat | the slow brown cat |
| the quick brown fox | the slow brown fox | the fast brown fox | conflict |
| none | the quick brown fox | the quick brown fox jumped | conflict |

- **Good for:** notes, descriptions, titles, any prose two people might edit.
- **Needs a base:** Yes. Without one, equal text merges. Different text is a conflict, since there's no telling which
  side's words are new.
- **Words:** a word is a run of letters, digits and apostrophes, together with the spaces and punctuation
  after it, so joining the words gives back the exact text. Every platform splits text the same way.
- **Called directly**, it takes any `StringProtocol`, such as `Substring`. Only `String` is `Codable`, so
  it's the only type a property can use it on.

## .keep

`KeepOursMerge` and `KeepTheirsMerge` always keep one side when both sides changed the value. A value only
one side changed still keeps that change.

```swift
@Merged(.keep(.ours)) var draft = ""              // only this device finishes it
@Merged(.keep(.theirs)) var cachedTotal = 0       // the other side recomputed it
```

| Base | Ours | Theirs | `.keep(.ours)` | `.keep(.theirs)` |
| --- | --- | --- | --- | --- |
| a | b | c | b | c |
| a | a | c | c | c |
| none | b | c | b | c |

- **Good for:** derived or cached values, and values one side owns.
- **Needs a base:** No. The answer is the same with or without one.
- **Conflicts:** never.

## .maximum

`ComparableMaximumMerge` keeps the larger value, by the type's own `<`.

```swift
@Merged(.maximum) var highScore = 0
@Merged(.maximum) var lastSeen: Date = .distantPast
@Merged(.maximum) var level: Level = Level(number: 1)    // a Comparable type of your own
```

| Base | Ours | Theirs | Result |
| --- | --- | --- | --- |
| 10 | 30 | 20 | 30 |
| none | 30 | 50 | 50 |

- **Good for:** high scores, furthest progress, latest dates, version numbers.
- **Needs a base:** No. It gives the same answer without one, since the larger value doesn't depend on
  history.
- **Never conflicts.**
- **Watch for:** a value that should be able to go down, such as a score after a reset. A decrease on one
  side loses to an increase on the other.

## .mergeable

`MergeableMerge` merges a value of a `Mergeable` type by the type's own `merging` functions, favoring the
named side where both changed the same thing.

```swift
@Merged(.mergeable(favoring: .theirs)) var tally: Tally = Tally()    // a Mergeable type of your own
```

- **Good for:** a type that knows how to merge itself, such as a counter or a document model.
- **Needs a base:** No. Without one it uses the type's two-way `merging`.
- **Conflicts:** only where the type's merge throws, which is `nil` here.
- **Watch for:** the type's base must be the type itself.

## .sum

`NumericSumMerge` adds both sides' changes to the base, as a counter does: `ours + theirs - base`.

```swift
@Merged(.sum) var wins = 0
@Merged(.sum) var distance = 0.0
```

| Base | Ours | Theirs | Result |
| --- | --- | --- | --- |
| 3 | 4 | 4 | 5 (both added one) |
| 3 | 5 | 1 | 3 (+2 and −2) |
| 10 | 12 | 8 | 10 |
| Int.max − 1 | Int.max | Int.max | conflict (overflow) |
| none | 4 | 5 | conflict |

- **Good for:** counters, tallies, balances changed by deltas, likes, visits.
- **Needs a base:** Yes. Without one, equal values merge. Different values are a conflict, since there's no telling how
  much each side added.
- **Conflicts:** without a base, and when a whole number would overflow, such as two `+1`s to
  `Int.max - 1`.
- **Watch for:** a value set outright rather than incremented. Setting 3 to 10 on both sides gives 17.

## .total

`CodableTotalMerge` merges node by node like `.byNode`, but never fails. Every change that doesn't clash
still applies, from both sides, and a value both sides changed differently takes the favored side, as
`git merge -X theirs` does.

```swift
@Merged(.total(favoring: .theirs)) var place: Place = Place()   // never a conflict
```

| Base | Ours | Theirs | `favoring: .ours` | `favoring: .theirs` |
| --- | --- | --- | --- | --- |
| {Elm, Oslo} | {Oak, Oslo} | {Elm, Bergen} | {Oak, Bergen} | {Oak, Bergen} |
| {Elm, Oslo} | {Oak, Bergen} | {Elm, Trondheim} | {Oak, Bergen} | {Oak, Trondheim} |
| none | {Oak, Oslo} | {Elm, Oslo} | {Oak, Oslo} | {Elm, Oslo} |

- **Good for:** a sync engine's default merge, which must always produce a record.
- **Needs a base:** No. Without one, every difference takes the favored side.
- **Conflicts:** never. Its `merge` never returns `nil`. A result that doesn't decode keeps that whole side.
- **Called directly**, the side is a value, so a sync engine that knows which side is newer picks one for
  each merge:

```swift
let merged = CodableTotalMerge<Note>(favoring: oursIsNewer ? .ours : .theirs).merge(base: base, ours: mine, theirs: yours)
```

## .trueWins

`BoolTrueWinsMerge` is `true` if either side is.

```swift
@Merged(.trueWins) var flagged = false
@Merged(.trueWins) var isRead = false
```

| Base | Ours | Theirs | Result |
| --- | --- | --- | --- |
| false | true | false | true |
| none | false | true | true |

- **Good for:** flags anyone can raise and nobody lowers, such as read, flagged, accepted and archived.
- **Needs a base:** No. It gives the same answer without one.
- **Never conflicts.**
- **Watch for:** a flag that can be cleared. If one side clears it while the other changed it too, `true`
  wins. A clear that only one side made still sticks, since the strategy isn't called.

## .union

`SetAlgebraUnionMerge` merges like `.byMembership` with a base. Without one, it keeps every element either
side has, so no addition is ever lost.

```swift
@Merged(.union) var recipients: Set<String> = []
```

| Base | Ours | Theirs | Result |
| --- | --- | --- | --- |
| {ana, bo} | {ana} | {ana, bo, cy} | {ana, cy} |
| none | {ana, cy} | {bo, ana} | {ana, bo, cy} |

- **Good for:** sets that should survive a first sync whole, such as recipients, collected items and seen
  IDs.
- **Needs a base:** No. Without one, it keeps everything from both sides.
- **Never conflicts.**
- **Watch for:** removals without a base. They're undone, since the other side's copy brings the element
  back.
