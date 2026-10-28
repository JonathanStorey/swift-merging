# Strategies

| Strategy | Type | Works with | With a base | Without a base |
| --- | --- | --- | --- | --- |
| [`.byNode`](#bynode) | `CodableNodeMerge` | any `Codable` | node by node | equal parts only |
| [`.byElement`](#byelement) | `RangeReplaceableCollectionElementMerge` | arrays, `String` | element by element | same length, element by element |
| [`.byKey`](#bykey) | `DictionaryKeyedMerge` | any `Codable` dictionary | key by key | same keys, value by value |
| [`.byMembership`](#bymembership) | `SetAlgebraMembershipMerge` | `Set`, any `OptionSet` | additions and removals from both | equal sets only |
| [`.byWord`](#byword) | `StringWordMerge` | `String` | word by word | conflict |
| [`.maximum`](#maximum) | `ComparableMaximumMerge` | any `Comparable` | the larger | the larger |
| [`.sum`](#sum) | `NumericSumMerge` | any `Numeric` | both changes added | conflict |
| [`.trueWins`](#truewins) | `BoolTrueWinsMerge` | `Bool` | `true` if either is | `true` if either is |
| [`.union`](#union) | `SetAlgebraUnionMerge` | `Set`, any `OptionSet` | additions and removals from both | everything from both |

## .byNode

`CodableNodeMerge` is the structured merge that every `Codable` type conforming to `Mergeable` uses by
default, with no code and no `@Merged`. It encodes the value into a tree, merges the tree node by node, and
decodes the result.

Where both sides changed a node:

- an object merges key by key;
- an array merges element by element, as `.byElement` does;
- a `Set` merges `.byMembership`;
- a `Dictionary` merges `.byKey`;
- a `@Merged` property merges by its strategy;
- a `Mergeable` property merges by its own type's merge;
- a `String`, number or `Bool` changed differently on both sides is a conflict.

```swift
struct Settings: Codable, Mergeable {           // merges by node, with no code
    var theme = "light"
    var favorites: [String] = []
}

@Merged(.byNode) var booking = Booking()        // ignores Booking's own merge
try CodableNodeMerge<Address>().merge(base: original, ours: mine, theirs: yours)
```

- **Good for:** any `Codable` value, including types from other libraries that can't be made `Mergeable`.
- **Without a base:** objects with the same keys merge key by key, and arrays of the same length element by
  element. Only equal values merge, along with values whose strategy works without a base.
- **Conflicts:** wherever both sides changed a plain value differently, or when the merged result doesn't
  decode, such as one that breaks a type's own validation.
- **On a property:** it overrides that type's own `merging(with:from:)`. A plain `Codable` property already
  merges by node, so the shorthand is only needed to override.
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

- **Good for:** ordered lists where position matters and duplicates are allowed, such as steps, playlists
  and layers.
- **Without a base:** on a property, lists of the same length merge element by element, so only equal
  elements, or elements with a strategy of their own, merge. Called directly, only equal lists merge. An
  inserted or removed element changes the length and is a conflict.
- **An element both sides changed:** on a property, it merges by the element's own merge, so two people
  editing different fields of the same item both keep their changes. Called directly, elements match by
  `==`, so different replacements of the same element are a conflict.
- **Conflicts:** only when both sides replaced the same element differently and the replacements can't
  merge. Different insertions at the same spot are both kept, ours first.
- **Watch for:** moves. A move is a removal plus an insertion, so two people moving the same element to
  different places keep both copies.
- Arrays already merge this way by default, so on an array the shorthand states intent. On a `String` it
  changes the behavior, since text conflicts by default.

## .byKey

`DictionaryKeyedMerge` merges a dictionary key by key, whatever the key's type. A key only one side added,
changed or removed keeps that side. A key both sides changed merges its values, honoring any strategies
inside them.

```swift
@Merged(.byKey) var pins: [Spot: String] = [:]
@Merged(.byKey) var scores: [String: Int] = [:]
```

| Base | Ours | Theirs | Result |
| --- | --- | --- | --- |
| [a: 1] | [a: 1, b: 2] | [:] | [b: 2] |
| [a: 1] | [a: 2] | [a: 3] | conflict |

- **Good for:** settings by name, scores by player, any lookup table.
- **Without a base:** dictionaries with the same keys merge value by value. Different keys conflict, since
  there's no telling an added key from a removed one.
- **Conflicts:** when one side removed a key the other changed, or when both changed a value that can't
  merge.
- Every `Dictionary` merges this way by default. Struct keys work too: a dictionary whose keys aren't
  `String` or `Int` encodes as a flat list, and this strategy lines the keys back up.
- **Called directly**, it takes any `Codable` type written as a dictionary literal, such as an ordered
  dictionary.

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

- **Good for:** tags, selected options, permissions, followers.
- **Without a base:** only equal sets merge, since there's no telling an addition from a removal. Use
  `.union` to keep both sides instead.
- **Never conflicts with a base.**
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

- **Good for:** notes, descriptions, titles, any prose two people might edit.
- **Without a base:** conflict, since there's no telling which side's words are new.
- **Words:** a word is a run of letters, digits and apostrophes, together with the spaces and punctuation
  after it, so joining the words gives back the exact text. Every platform splits text the same way.
- **Called directly**, it takes any `StringProtocol`, such as `Substring`. Only `String` is `Codable`, so
  it's the only type a property can use it on.

## .maximum

`ComparableMaximumMerge` keeps the larger value, by the type's own `<`.

```swift
@Merged(.maximum) var highScore = 0
@Merged(.maximum) var lastSeen = Date.distantPast
@Merged(.maximum) var level = Level(number: 1)    // a Comparable type of your own
```

| Base | Ours | Theirs | Result |
| --- | --- | --- | --- |
| 10 | 30 | 20 | 30 |
| none | 30 | 50 | 50 |

- **Good for:** high scores, furthest progress, latest dates, version numbers.
- **Without a base:** the same answer, since the larger value doesn't depend on history.
- **Never conflicts.**
- **Watch for:** a value that should be able to go down, such as a score after a reset. A decrease on one
  side loses to an increase on the other.

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

- **Good for:** counters, tallies, balances changed by deltas, likes, visits.
- **Without a base:** conflict, since there's no telling how much each side added.
- **Conflicts:** when a whole number would overflow, such as two `+1`s to `Int.max - 1`.
- **Watch for:** a value set outright rather than incremented. Setting 3 to 10 on both sides gives 17.

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
- **Without a base:** the same answer.
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
- **Without a base:** keeps everything from both sides.
- **Never conflicts.**
- **Watch for:** removals without a base. They're undone, since the other side's copy brings the element
  back.
