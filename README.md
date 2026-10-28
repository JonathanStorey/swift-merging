# Merging

Strategies for merging two or three versions of a value, for sync engines and editors that meet the
same record changed in two places.

```swift
import Merging

struct Note: Codable, Mergeable {
    var title = ""                                  // keeps the side that changed
    var address = Address()                         // merges by Address's own merge, if it has one
    @Merged(.maximum) var highScore = 0             // keeps the larger when both changed
}

var draft = mine
try draft.merge(with: yours, from: original)             // or draft.merging(with: yours, from: original)
```

## Mergeable

`Mergeable` has one requirement, `merging(with:from:)`, which merges `theirs` into a value, which is ours,
knowing their common ancestor. A merge throws a `MergeConflict` holding the versions when it can't merge
them. The mutating `merge(with:from:)` leaves the value unchanged on a conflict, and the static
`merge(base:ours:theirs:)` is there too.

Without an ancestor there's no telling which side changed, so the two-way `merging(with:)` throws a conflict
unless the type knows how to merge without one.

There are three ways to conform, from least to most code:

1. **A `Codable` type conforms with no code.** It merges node by node with `CodableNodeMerge`, a
   structured merge through a tree of its encoded form, without
   going through JSON text. A property only one side changed keeps that side. Where both changed it, a
   `Mergeable` property merges by its type's own merge, an object or dictionary key by key, an array
   element by element (both sides' insertions kept, ours first), a set by keeping what either side added
   and dropping what either removed, and anything else is a conflict. The result must decode, or
   the merge is a conflict. Two-way, only what's equal merges, plus properties that can merge without a
   base.
2. **`@Merged(_:)` picks a property's `MergeStrategy`**, for a type that merges differently in different
   places, such as an `Int` that's a counter in one property and a high score in another. The wrapper
   encodes as its bare value, so adding it doesn't change what's stored.
3. **Write `merging(with:from:)` yourself** to merge the whole value your own way:

```swift
struct Booking: Codable, Mergeable {
    var note = ""
    var confirmed = false

    func merging(with theirs: Booking, from base: Booking) -> Booking {
        confirmed ? self : theirs
    }
}
```

The tree merge encodes and decodes on every merge, which suits syncing rather than tight loops.

## Strategies

The standard strategies take dot syntax, with no parentheses:

```swift
struct Game: Codable, Mergeable {
    @Merged(.maximum) var highScore = 0             // the larger, by the type's own <
    @Merged(.sum) var wins = 0                      // a counter: both sides' increments count
    @Merged(.trueWins) var flagged = false          // a flag anyone can set
    @Merged(.byWord) var note = ""                  // edits to different words combine
    @Merged(.byMembership) var tags: Set<String> = []   // who's in it
    @Merged(.union) var recipients: Set<String> = []    // never loses an addition, even without a base
    @Merged(.byKey) var pins: [Spot: String] = [:]      // key by key, whatever the key
}
```

| Shorthand | Strategy | Suits | Needs a base |
| --- | --- | --- | --- |
| `.maximum` | `ComparableMaximumMerge` | any `Comparable` | no |
| `.sum` | `NumericSumMerge` | any `Numeric` | yes |
| `.trueWins` | `BoolTrueWinsMerge` | `Bool` | no |
| `.byWord` | `StringWordMerge` | `String` (any `StringProtocol` when called directly) | yes |
| `.byMembership` | `SetAlgebraMembershipMerge` | any `SetAlgebra`, such as `Set` or an `OptionSet` | yes |
| `.union` | `SetAlgebraUnionMerge` | any `SetAlgebra` | no |
| `.byKey` | `DictionaryKeyedMerge` | any `Codable` dictionary | no |
| `.byElement` | `RangeReplaceableCollectionElementMerge` | arrays element by element, `String` by character | yes |
| `.byNode` | `CodableNodeMerge` | any `Codable`, overriding a type's own merge | no |

[Strategies/README.md](Sources/Merging/Strategies/README.md) covers each one in detail, including how it
behaves without a base. Each is named for the type it suits, then its shorthand, then `Merge`. A strategy decides only when both
sides changed a property, even to the same value, so two increments of a counter both count. Sets merge
`.byMembership` and dictionaries `.byKey` without naming a strategy. A mismatch such as
`@Merged(.byWord) var count = 0` doesn't compile.

`$` merges one property by its strategy, as the whole value's merge would:

```swift
try game.$wins.merge(with: theirs.wins, from: base.wins)
let best = try game.$highScore.merging(with: 20, from: 10)
```

Every standard strategy is typed, so it also merges plain values:

```swift
ComparableMaximumMerge<Int>().merge(base: 1, ours: 5, theirs: 3)    // 5
```

### Writing a strategy

A strategy of your own works on the property's own type. It implements the three-way merge, and the
two-way merge too if it needs no ancestor. It's made with `init()` when a value decodes, so it holds no
settings of its own. A non-generic strategy whose merge doesn't throw names its value with
`typealias Value`.

```swift
struct LongerMerge: MergeStrategy {
    typealias Value = String

    func merge(base: String, ours: String, theirs: String) -> String {
        ours.count >= theirs.count ? ours : theirs
    }
}

extension MergeStrategy where Self == LongerMerge {
    static var longer: LongerMerge { LongerMerge() }
}

@Merged(.longer) var title = ""
```

A strategy for one concrete type gets its shorthand as above. A generic one, such as
`ComparableMaximumMerge<Value>`, can't, since a static property can't be generic. The standard ones get
around this with a non-generic shortcut type, such as `MaximumShortcut`, whose own `@Merged` initializer
checks the property's type. Without a shortcut, a generic strategy of your own takes a shorthand per
concrete type, as Foundation's `.number` format does, or is written out: `@Merged(LargestMerge())`.

A `TreeMergeStrategy` works on the property's `CodableTree` instead, so one strategy suits many types. It
declares the types it suits with one initializer, and `typed(as:)` turns it into a typed strategy:

```swift
extension Merged where Strategy == ShoutMerge {
    public init(wrappedValue: Value, _ strategy: ShoutMerge) where Value == String {
        self.init(wrappedValue: wrappedValue, unchecked: strategy)
    }
}

try ShoutMerge().typed(as: String.self).merge(base: "a", ours: "b", theirs: "c")
```

On Swift 6.1, a generic strategy that throws a conflict of a type built from its generic parameters, such
as `MergeConflict<Set<Element>>`, crashes the compiler, so the standard strategies are generic over the
whole type. Swift 6.2 fixes it.

## CodableTree

`CodableTree` is a value's stored form, as JSON would hold it: `null`, `bool`, `int`, `uint`, `double`,
`string`, `array`, or `object`.

```swift
let tree = try CodableTree(encoding: point)      // {"x": 1, "y": 2.5}
tree["x"]?.int                                   // 1
let copy = try tree.decode(as: Point.self)
let literal: CodableTree = ["tags": ["a", "b"], "count": 2]
```

Its nodes can be edited in place, reached by path, walked, and compared:

```swift
var tree = try CodableTree(encoding: person)
tree["address"]?["city"] = "Bergen"                 // setting nil removes
tree[["tags", 0]]?.string                           // a path of keys and indices
tree.children                                       // the nodes directly inside
tree.forEach { path, node in print(path, node) }    // every node, depth first
tree.difference(from: original)                     // ["~ age: 30 → 31", "+ tags[2]: \"c\""]
```

## Requirements

Swift 6.1 (Xcode 16.3) or later, for typed throws and Swift Testing. iOS 17, macOS 14, tvOS 17, watchOS 10 and
visionOS 1, or Linux.

```swift
.package(url: "https://github.com/JonathanStorey/swift-merging.git", branch: "main")
```
