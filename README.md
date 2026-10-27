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
try draft.merge(yours, base: original)             // or draft.merging(yours, base: original)
```

## Mergeable

`Mergeable` has one requirement, `merging(_:base:)`, which merges `theirs` into a value, which is ours,
knowing their common ancestor. A merge throws a `MergeConflict` holding the versions when it can't merge
them. The mutating `merge(_:base:)` leaves the value unchanged on a conflict, and the static
`merge(base:ours:theirs:)` is there too.

Without an ancestor there's no telling which side changed, so the two-way `merging(_:)` throws a conflict
unless the type knows how to merge without one.

There are three ways to conform, from least to most code:

1. **A `Codable` type conforms with no code.** It merges through a snapshot of its encoded form, without
   going through JSON text. A property only one side changed keeps that side. Where both changed it, a
   `Mergeable` property merges by its type's own merge, an object or dictionary key by key, an array
   element by element (both sides' insertions kept, ours first), a set by keeping what either side added
   and dropping what either removed, and anything else is a conflict. The result must decode, or
   the merge is a conflict. Two-way, only what's equal merges, plus properties that can merge without a
   base.
2. **`@Merged(_:)` picks a property's `MergeStrategy`**, for a type that merges differently in different
   places, such as an `Int` that's a counter in one property and a high score in another. The wrapper
   encodes as its bare value, so adding it doesn't change what's stored.
3. **Write `merging(_:base:)` yourself** to merge the whole value your own way:

```swift
struct Booking: Codable, Mergeable {
    var note = ""
    var confirmed = false

    func merging(_ theirs: Booking, base: Booking) -> Booking {
        confirmed ? self : theirs
    }
}
```

The snapshot merge encodes and decodes on every merge, which suits syncing rather than tight loops.

## Strategies

The standard strategies take dot syntax:

```swift
struct Game: Codable, Mergeable {
    @Merged(.maximum) var highScore = 0             // the larger number, text, or date
    @Merged(.adding) var wins = 0                   // a counter: both sides' increments count
    @Merged(.trueWins) var flagged = false          // a flag anyone can set
    @Merged(.byWord) var note = ""                  // edits to different words combine
    @Merged(.byMembership) var tags: [String] = []  // who's in it, ignoring order
    @Merged(.union) var recipients: [String] = []   // never loses an addition, even without a base
}
```

Sets merge `.byMembership` and dictionaries `.byKey` without naming a strategy. A `.by` name says what
unit is merged, and the others say what wins.

A strategy decides only when both sides changed a property, even to the same value, so two increments of
a counter both count. `.maximum` and `.trueWins` also merge without a base. `.adding` and `.byWord` need one.

The standard strategies work on a property's `Snapshot`, its stored form, and each declares the types it
suits, so a mismatch such as `@Merged(.byWord) var count = 0` doesn't compile. A `SnapshotMergeStrategy` of
your own does the same with one initializer:

```swift
extension Merged where Strategy == ShoutMerge {
    public init(wrappedValue: Value, _ strategy: ShoutMerge) where Value == String {
        self.init(wrappedValue: wrappedValue, unchecked: strategy)
    }
}
```

`.maximum` accepts any `Comparable`, but compares the stored form, so a struct of your own is a conflict.
Give it a typed strategy instead.

`typed(as:)` turns a snapshot strategy into a typed one, to merge plain values with it:

```swift
try MaxMerge().typed(as: Int.self).merge(base: 1, ours: 5, theirs: 3)    // 5
```

A strategy of your own can be typed, working on the property's own type:

```swift
struct Higher<Value: Comparable & Sendable>: MergeStrategy {
    func merge(base: Value, ours: Value, theirs: Value) -> Value { max(ours, theirs) }
    func merge(ours: Value, theirs: Value) -> Value { max(ours, theirs) }
}

@Merged(Higher()) var level = Level(number: 1)      // uses Level's own <
```

It implements the three-way merge, and the two-way merge too if it needs no ancestor. It's made with
`init()` when a value decodes, so it holds no settings of its own. A non-generic strategy whose merge
doesn't throw names its value with `typealias Value`.

On Swift 6.1, a generic strategy that throws a conflict of a collection type, such as
`MergeConflict<Set<Element>>`, crashes the compiler. Swift 6.2 fixes it.

## Snapshot

`Snapshot` is a value's stored form, as JSON would hold it: `null`, `bool`, `int`, `uint`, `double`,
`string`, `array`, or `object`.

```swift
let snapshot = try Snapshot(encoding: point)      // {"x": 1, "y": 2.5}
snapshot["x"]?.int                                // 1
let copy = try snapshot.decode(as: Point.self)
let literal: Snapshot = ["tags": ["a", "b"], "count": 2]
```

## Requirements

Swift 6.1 (Xcode 16.3) or later, for typed throws and Swift Testing. iOS 17, macOS 14, tvOS 17, watchOS 10 and
visionOS 1, or Linux.

```swift
.package(url: "https://github.com/JonathanStorey/swift-merging.git", branch: "main")
```
