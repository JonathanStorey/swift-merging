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
draft.merge(with: yours, from: original)                 // or draft.merging(with: yours, from: original)
```

## Mergeable

`Mergeable` has one requirement, `merging(with:from:)`, which merges `theirs` into a value, which is ours,
knowing their common ancestor. It returns `nil` when the versions can't be merged, a conflict, and the
caller decides what happens next with the versions it already holds. The mutating `merge(with:from:)`
returns whether it merged and leaves the value unchanged on a conflict, and the static
`merge(base:ours:theirs:)` is there too.

```swift
guard let merged = mine.merging(with: yours, from: original) else {
    // a conflict: keep one side, ask the user, or use what the sync layer knows
}
```

Without an ancestor there's no telling which side changed, so the two-way `merging(with:)` returns `nil`
unless the type knows how to merge without one. With `@Merged`, `$property.merging(with:from:)` shows
which property conflicts.

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

The tree merge encodes and decodes on every merge, which fits syncing better than tight loops.

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
    @Merged(.keep(.theirs)) var rank = 0                // always the other side's when both changed
}
```

[Strategies/README.md](Sources/Merging/Strategies/README.md) details each strategy, with examples and how
it behaves without a base. Sets merge `.byMembership` and dictionaries `.byKey` without naming a strategy. A
mismatch such as `@Merged(.byWord) var count = 0` doesn't compile.

### When a strategy runs

A strategy only decides when both sides changed a value. Before it's called, the merge settles the easy
cases: if theirs equals the base, ours wins, and if ours equals the base, theirs wins. So a strategy always
sees two real edits, even two equal ones, and two increments of a counter both count.

### Merging without a base

A three-way merge knows what each side started from. A two-way merge only has ours and theirs, which costs
it three things:

1. **It can't tell who changed what.** Any difference counts as both sides changing it, so every
   difference goes to the strategy.
2. **It can't tell an addition from a removal.** If ours has `x` and theirs doesn't, either ours added it
   or theirs removed it.
3. **It can't measure a change.** A counter at 5 on one side and 7 on the other could have started
   anywhere.

So without a base, each strategy does one of four things:

| Behavior | Strategies | Why |
| --- | --- | --- |
| **The same answer** | `.maximum`, `.trueWins`, `.keep`, `.total(favoring:)` | the result doesn't depend on history |
| **A looser answer** | `.union` | keeps everything from both sides, so removals are undone |
| **Merges only what matches** | `.byNode`, `.byElement`, `.byKey`, `.byMembership` | equal parts merge, and any difference conflicts |
| **Merges only equal values** | `.sum`, `.byWord` | any difference needs the base |

"Merges only what matches" works structurally. Objects with the same keys merge key by key, and lists of
the same length element by element, so a strategy deeper inside still gets its say.

A conflict without a base is the honest answer. It hands the caller both versions, and the caller can pick
one with information the merge doesn't have, such as which device wrote last.

### Merging one property

`$` merges one property by its strategy, as the whole value's merge would:

```swift
game.$wins.merge(with: theirs.wins, from: base.wins)
let best = game.$highScore.merging(with: 20, from: 10)     // Int?
```

Every standard strategy is typed, so it also merges plain values:

```swift
ComparableMaximumMerge<Int>().merge(base: 1, ours: 5, theirs: 3)    // 5
```

### Writing a strategy

A strategy of your own works on the property's own type. It implements the three-way merge, and the
two-way merge too if it needs no ancestor, and returns `nil` for versions it can't merge. It's made with
`init()` when a value decodes, so it holds no settings of its own.

```swift
struct LongerMerge: MergeStrategy {
    typealias Value = String

    func merge(base: String, ours: String, theirs: String) -> String? {
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

A `TreeMergeStrategy` works on the property's `CodableTree` instead, so one strategy works with many types. It
declares the types it works with with one initializer, and `typed(as:)` turns it into a typed strategy:

```swift
extension Merged where Strategy == ShoutMerge {
    public init(wrappedValue: Value, _ strategy: ShoutMerge) where Value == String {
        self.init(wrappedValue: wrappedValue, unchecked: strategy)
    }
}

ShoutMerge().typed(as: String.self).merge(base: "a", ours: "b", theirs: "c")
```

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

## SwiftData (experimental)

`MergingSwiftData` merges a SwiftData model property by property when another context, process, or device
saves the same object. It reads the store's history to see what changed, and takes the base, the values
before the other side's save, from Core Data's own report of that save as it happens, with a ledger as a
fallback. CloudKit imports merge against the last version both devices agreed on, which finished exports
keep current. Needs iOS 18 or macOS 15.

```swift
import MergingSwiftData

@Model @MergeableModel
final class Note {
    @Merge(.byWord) var body = ""                       // edits to different words combine
    @Merge(.sum) var likes = 0                          // both sides' increments count
    @Merge(.keep(.theirs)) @Attribute(.externalStorage) var photo: Data?
    var color = "red"                                   // no @Merge: as SwiftData would
    @Merge(.byMembership) @Relationship var tags: [Tag] = []
}

let container = try ModelContainer(for: Note.self)
try container.enableMerging(Note.self)                  // nothing else to call
```

`@Merge` takes the same strategies as `@Merged`, and is only for SwiftData models: on anything else it's a
compile error. `@MergeableModel` writes the model's `MergeableModel` conformance, a snapshot of every stored
property, since a SwiftData save writes the whole object and a property left out would lose the other
side's change. Merging is opt-in: a property or relationship without `@Merge` does what SwiftData alone
would, and only a `@Merge` strategy merges three ways, from the base, ours and theirs. A to-many relationship merges as a set, by
`.byMembership`, since SwiftData doesn't keep its order. `@Transient` properties are left out.

A property without `@Merge`, or whose strategy can't combine two changes, takes the conflict policy's side.
The default, `.storeDefault`, keeps what SwiftData would without merging: the main context's save over
another context's, and a CloudKit import over this device's earlier save, which is CloudKit's server wins.
`.keepOurs` and `.keepTheirs` choose a side instead.

## Requirements

Swift 6.1 (Xcode 16.3) or later. iOS 17, macOS 14, tvOS 17, watchOS 10 and
visionOS 1, or Linux.

```swift
.package(url: "https://github.com/JonathanStorey/swift-merging.git", branch: "main")
```
