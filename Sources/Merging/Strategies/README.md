# Strategies

The pre-built merge strategies, one per file. Each is a typed `MergeStrategy`, named for the type it
suits, then its shorthand, then `Merge`: `ComparableMaximumMerge` is `.maximum` for any `Comparable`.

## How a strategy runs

A strategy only decides when **both sides changed** a value. Before it's called, the merge settles the
easy cases:

- Theirs equals the base: ours wins.
- Ours equals the base: theirs wins.

So `merge(base:ours:theirs:)` always sees two real edits, even two equal ones. That matters for `.sum`:
two `+1`s both count.

`merge(ours:theirs:)` runs when there is **no base at all**, such as on a first sync or when two devices
created the same record independently. A strategy implements it only when it has one right answer without
history. Otherwise the default throws a `MergeConflict`.

Every strategy can be used three ways:

```swift
@Merged(.maximum) var highScore = 0                                // on a property
try game.$highScore.merge(with: theirs.highScore, from: base.highScore)  // one property by hand
ComparableMaximumMerge<Int>().merge(base: 1, ours: 5, theirs: 3)   // on plain values: 5
```

Putting a shorthand on a type it doesn't suit, such as `@Merged(.byWord) var count = 0`, doesn't compile.

## At a glance

| Shorthand | Strategy | Suits | Three-way | Two-way |
| --- | --- | --- | --- | --- |
| `.maximum` | `ComparableMaximumMerge` | any `Comparable` | the larger | the larger |
| `.sum` | `NumericSumMerge` | any `Numeric` | both changes added | conflict |
| `.trueWins` | `BoolTrueWinsMerge` | `Bool` | `true` if either is | `true` if either is |
| `.byWord` | `StringWordMerge` | `String` | word by word | conflict |
| `.byElement` | `RangeReplaceableCollectionElementMerge` | arrays, `String` | element by element | same length, element by element |
| `.byMembership` | `SetAlgebraMembershipMerge` | `Set`, any `OptionSet` | adds and removes from both | only if equal |
| `.union` | `SetAlgebraUnionMerge` | `Set`, any `OptionSet` | adds and removes from both | everything from both |
| `.byKey` | `DictionaryKeyedMerge` | any `Codable` dictionary | key by key | same keys, value by value |
| `.byNode` | `CodableNodeMerge` | any `Codable` | node by node | node by node, equal parts only |

## Without a base

A three-way merge knows what each side started from. A two-way merge only has ours and theirs, which costs
it three things:

1. **It can't tell who changed what.** With a base, a value only one side changed simply keeps that side.
   Without one, any difference counts as both sides changing it, so every difference goes to the strategy.
2. **It can't tell an addition from a removal.** If ours has `x` and theirs doesn't, either ours added it
   or theirs removed it. Sets, dictionaries and lists can't merge their differences safely.
3. **It can't measure a change.** A counter at 5 on one side and 7 on the other could have started
   anywhere, so there's no sum.

So without a base, each strategy does one of four things:

| Behavior | Strategies | Why |
| --- | --- | --- |
| **Same answer as with a base** | `.maximum`, `.trueWins` | the result doesn't depend on history |
| **A different, looser answer** | `.union` | keeps everything from both sides, so removals are undone |
| **Merges only what matches** | `.byMembership`, `.byElement`, `.byKey`, `.byNode` | equal parts merge; any difference is a conflict |
| **Always a conflict** | `.sum`, `.byWord` | the answer needs the base |

"Merges only what matches" works structurally: `.byKey` and `.byNode` merge objects with the same keys
key by key, and lists of the same length element by element, so a strategy deeper inside still gets its
say. A `.trueWins` flag inside a struct still merges without a base, as long as the struct's other fields
match.

A conflict without a base is the honest answer, not a failure. It hands the caller both versions, and the
caller can pick one with information the merge doesn't have, such as which device wrote last.

## Defaults

Without `@Merged`, a `Codable` `Mergeable` type merges by `.byNode`, and inside it:

- a `Set` merges `.byMembership`;
- a `Dictionary` merges `.byKey`;
- an array merges element by element, as `.byElement` does;
- a `Mergeable` property merges by its own type's merge;
- a `String`, number or `Bool` both sides changed differently is a conflict.

The defaults only merge what has one right answer. Anything that needs a judgment, such as adding versus
taking the larger, is a strategy you choose.

---

## `.maximum` — `ComparableMaximumMerge`

Keeps the larger value, by the type's own `<`.

```swift
@Merged(.maximum) var highScore = 0
@Merged(.maximum) var lastSeen = Date.distantPast
@Merged(.maximum) var level = Level(number: 1)    // your own Comparable type
```

| Base | Ours | Theirs | Result |
| --- | --- | --- | --- |
| 10 | 30 | 20 | 30 |
| — | 30 | 50 | 50 |

- **Suits:** high scores, furthest progress, latest dates, version numbers.
- **Without a base:** works, since the larger value doesn't depend on history.
- **Never conflicts.**
- **Watch for:** a value that should be able to go down, such as a score after a reset. A decrease on one
  side loses to an increase on the other.
- Named `maximum`, not `max`, because a static `max` would hide `Swift.max` inside strategies.

## `.sum` — `NumericSumMerge`

Adds both sides' changes to the base, as a counter does: `ours + theirs - base`.

```swift
@Merged(.sum) var wins = 0
@Merged(.sum) var distance = 0.0
```

| Base | Ours | Theirs | Result |
| --- | --- | --- | --- |
| 3 | 4 | 4 | 5 (both added one) |
| 3 | 5 | 1 | 3 (+2 and −2) |
| 10 | 12 | 8 | 10 |

- **Suits:** counters, tallies, balances changed by deltas, likes, visits.
- **Without a base:** conflict, since there's no telling how much each side added.
- **Conflicts:** when a whole number would overflow, such as two `+1`s to `Int.max - 1`.
- **Watch for:** a value set outright rather than incremented. Setting 3 to 10 on both sides gives 17.

## `.trueWins` — `BoolTrueWinsMerge`

`true` if either side is.

```swift
@Merged(.trueWins) var flagged = false
@Merged(.trueWins) var isRead = false
```

| Base | Ours | Theirs | Result |
| --- | --- | --- | --- |
| false | true | false | true |
| — | false | true | true |

- **Suits:** flags anyone can raise and nobody lowers: read, flagged, accepted, archived.
- **Without a base:** works.
- **Never conflicts.**
- **Watch for:** a flag that can be cleared. If one side clears it while the other changed it too, `true`
  wins. A clear that only one side made still sticks, since the strategy isn't called.

## `.byWord` — `StringWordMerge`

Splits text into words, merges the word lists like lines in a three-way text merge, and joins them back.
Edits to different words combine. Edits to the same word conflict.

```swift
@Merged(.byWord) var note = ""
```

| Base | Ours | Theirs | Result |
| --- | --- | --- | --- |
| the quick brown fox | the slow brown fox | the quick brown cat | the slow brown cat |
| the quick brown fox | the slow brown fox | the fast brown fox | conflict |

- **Suits:** notes, descriptions, titles, any prose two people might edit.
- **Without a base:** conflict.
- **Words:** a word is a run of letters, digits and apostrophes, together with the spaces and punctuation
  after it, so joining the words gives back the exact text. The rule is the same on every platform, so
  every device splits text alike.
- **Called directly**, it takes any `StringProtocol`, such as `Substring`. Only `String` is `Codable`, so
  it's the only type a property can use it on.

## `.byElement` — `RangeReplaceableCollectionElementMerge`

Merges a list element by element, like a three-way merge of lines. An element either side removed is
removed, and what each side inserted goes where it was inserted, ours first. On a `String`, it merges
character by character.

```swift
@Merged(.byElement) var steps: [String] = []
@Merged(.byElement) var code = ""
```

| Base | Ours | Theirs | Result |
| --- | --- | --- | --- |
| [boil, stir, serve] | [boil, salt, stir, serve] | [stir, serve, eat] | [salt, stir, serve, eat] |
| soup | soups | Soup | Soups |

- **Suits:** ordered lists where position matters and duplicates are allowed: steps, playlists, layers.
- **Without a base:** on a property, lists of the same length merge element by element, so only equal
  elements, or elements with a strategy of their own, merge. Called directly, only equal lists merge.
  An inserted or removed element changes the length and is a conflict.
- **An element both sides changed:** on a property, it merges by the element's own merge, so two people
  editing different fields of the same player both keep their changes. Called directly, elements match by
  `==`, so different replacements of the same element are a conflict.
- **Conflicts:** only when both sides replaced the same element differently and the replacements can't
  merge. Different insertions at the same spot are both kept, ours first.
- **Watch for:** moving an element. A move is a removal plus an insertion, so two people moving the same
  element to different places keep both copies.
- Arrays already merge this way by default, so the shorthand mainly states intent. On a `String` it
  changes the behavior, since text conflicts by default.

## `.byMembership` — `SetAlgebraMembershipMerge`

Merges by what each side added and removed: an element is kept if either side added it, and removed if
either side removed it.

```swift
@Merged(.byMembership) var tags: Set<String> = []
@Merged(.byMembership) var shipping: Shipping = []    // an OptionSet
```

| Base | Ours | Theirs | Result |
| --- | --- | --- | --- |
| {a, b, c} | {a, c, ours} | {a, b, theirs} | {a, ours, theirs} |

- **Suits:** tags, selected options, permissions, followers.
- **Without a base:** only equal sets merge, since there's no telling an addition from a removal.
- **Never conflicts with a base.**
- Every `Set` merges this way by default. The shorthand is what lets an `OptionSet` merge by membership.

## `.union` — `SetAlgebraUnionMerge`

The same as `.byMembership` with a base. Without one, it keeps every element either side has, so no
addition is ever lost.

```swift
@Merged(.union) var recipients: Set<String> = []
```

| Base | Ours | Theirs | Result |
| --- | --- | --- | --- |
| {ana, bo} | {ana} | {ana, bo, cy} | {ana, cy} |
| — | {ana, cy} | {bo, ana} | {ana, bo, cy} |

- **Suits:** sets that should survive a first sync whole: recipients, collected items, seen IDs.
- **Without a base:** works.
- **Watch for:** removals without a base. They're undone, since the other side's copy brings the element
  back.

## `.byKey` — `DictionaryKeyedMerge`

Merges a dictionary key by key, whatever the key's type. A key only one side added, changed or removed
keeps that side. A key both sides changed merges its values, honoring any strategies inside them.

```swift
@Merged(.byKey) var pins: [Spot: String] = [:]
@Merged(.byKey) var scores: [String: Int] = [:]
```

| Base | Ours | Theirs | Result |
| --- | --- | --- | --- |
| [a: 1] | [a: 1, b: 2] | [:] | [b: 2] |
| [a: 1] | [a: 2] | [a: 3] | conflict |

- **Suits:** settings by name, scores by player, any lookup table.
- **Without a base:** dictionaries with the same keys merge value by value. Different keys conflict.
- **Conflicts:** when one side removed a key the other changed, or when both changed a value that can't
  merge.
- Every `Dictionary` merges this way by default. Struct keys work too: a dictionary with keys other than
  `String` or `Int` encodes as a flat list, and this strategy lines the keys back up.
- **Called directly**, it takes any `Codable` type you can write as a dictionary literal, such as an
  ordered dictionary.

## `.byNode` — `CodableNodeMerge`

The structured merge every `Codable` `Mergeable` type uses by default. It encodes the value into a tree,
merges the tree node by node, and decodes the result. The rules are listed under [Defaults](#defaults).

```swift
@Merged(.byNode) var booking = Booking()                    // ignores Booking's own merge
try CodableNodeMerge<Address>().merge(base: original, ours: mine, theirs: yours)
```

- **Suits:** merging any `Codable` value directly, including types from other libraries that you can't
  make `Mergeable`.
- **Without a base:** only equal parts merge, plus parts with a strategy that works without one.
- **Conflicts:** wherever both sides changed a plain value differently, or the merged result doesn't
  decode, such as one that breaks a type's own validation.
- **On a property:** it overrides that type's own `merging(with:from:)`. A plain `Codable` property
  already merges node by node, so the shorthand is only needed to override.
- It encodes and decodes on every merge, which suits syncing rather than tight loops.

---

## Shortcuts

A static property can't be generic, so `.maximum` can't name `ComparableMaximumMerge<Value>` directly.
The generic strategies get their bare shorthand through a small non-generic shortcut type, such as
`MaximumShortcut`. Its own `@Merged` initializer checks the property's type, and at merge time it runs the
same logic as the typed strategy. `.trueWins` and `.byWord` suit one concrete type, so they name their
strategy directly.

To write a strategy of your own, see [Writing a strategy](../../../README.md#writing-a-strategy).
