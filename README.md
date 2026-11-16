# Merging

Strategies for merging two or three versions of one property, for sync engines and editors that meet the
same record changed in two places.

```swift
import Merging

struct Profile: Codable {
    @Merged(.keep(.ours)) var nickname = ""         // keeps ours when both changed
    @Merged(LongerMerge()) var title: String = ""   // a strategy of your own
    var bio = ""                                    // not merged
}

let nickname = mine.$nickname.merging(with: yours.nickname, from: original.nickname)
```

> **0.4.0 rewrite.** Merging is property-level now, with the `@Merged` macro, which works the same on a
> struct, a class, or a SwiftData `@Model`. Use the `0.3.0` tag for the property wrapper and whole-value
> merging.

## @Merged

`@Merged(strategy)` marks a stored property and writes `$name`, a `MergedProperty` of the property's value
and its strategy. The property itself is left as written, so it stores, encodes, and compares exactly as it
would without the macro.

```swift
public func merging(with theirs: Value, from base: Value) -> Value?    // three-way
public func merging(with theirs: Value) -> Value?                      // two-way
public mutating func merge(with theirs: Value, from base: Value) -> Bool
public mutating func merge(with theirs: Value) -> Bool
```

`merge` writes the merged value back to the property through `$name`'s setter, and returns whether it could
merge. A `let` property gets a read-only `$name`, with only `merging`.

```swift
mine.$nickname.merge(with: yours.nickname, from: original.nickname)
```

- A side only one changed keeps that side, and the strategy decides when both did. Equal changes still go
  to the strategy, since a counter both sides raised by 1 has gone up by 2. That check needs an
  `Equatable` value. For any other value, the strategy decides every merge.
- The two-way merge has no base. A strategy that needs a base merges only equal values without one.
- `nil` means the versions can't be merged.

`$name` has the property's access level. The property's type comes from its annotation, or from a string,
number, or `true`/`false` literal, so `@Merged(.keep(.ours)) var total = makeTotal()` needs `: Int`.

## Strategies

| Strategy | Type | Works with | Merges | Needs a base |
| --- | --- | --- | --- | --- |
| `.byElement` | `RangeReplaceableCollectionElementMerge` | arrays, `String` | element by element | yes |
| `.byKey` | `DictionaryKeyedMerge` | any `Dictionary` | key by key | yes |
| `.byNode` | `CodableNodeMerge` | any `Codable` | node by node | yes |
| `.byMembership` | `SetAlgebraMembershipMerge` | `Set`, any `OptionSet` | additions and removals from both | yes |
| `.byWord` | `StringWordMerge` | `String` | word by word | yes |
| `.keep(.ours)`, `.keep(.theirs)` | `KeepMerge` | anything | the named side | no |
| `.maximum` | `ComparableMaximumMerge` | any `Comparable` | the larger | no |
| `.sum` | `NumericSumMerge` | any `Numeric` | both changes added | yes |
| `.total(favoring:)` | `CodableTotalMerge` | any `Codable` | node by node, clashes to one side | no |
| `.trueWins` | `BoolTrueWinsMerge` | `Bool` | `true` if either is | no |
| `.union` | `SetAlgebraUnionMerge` | `Set`, any `OptionSet` | additions and removals from both, everything without a base | no |

A strategy that needs a base merges only equal values in a two-way merge. `.byElement`, `.byKey` and
`.byWord` match by `==`, so a place both sides changed differently can't be merged. `.byNode` merges such a
place node by node instead. [Strategies](Sources/Merging/Strategies/README.md) shows each one with examples.

The shorthand is a `MergeShorthand`. Most strategies are generic over the property's type, which an
attribute can't see, so the macro writes the shorthand out as its strategy: `.keep(.ours)` on a `String`
becomes `KeepMerge<String>(.ours)`.

## Writing a strategy

Implement the three-way merge, and the two-way merge too if the strategy needs no ancestor. A strategy is a
plain value, so it can hold settings.

```swift
struct LongerMerge: MergeStrategy {
    func merge(base: String, ours: String, theirs: String) -> String? {
        ours.count >= theirs.count ? ours : theirs
    }
}
```

Without a two-way merge, an `Equatable` value merges only when both sides are equal.

## Representations

`CodableRepresentation` is a value's stored form: what its `Codable` conformance encodes. A `Date`, `Data`,
`UUID`, `Decimal` or `URL` keeps its type, and a `Set` is a `.set`, so a value round-trips exactly and a store with types of its own
can map each one. `dictionary()` gives an object's fields one level deep, keyed by property name, which suits
a `CKRecord`'s fields. A nested value stays one value.

```swift
let representation = try CodableRepresentation(encoding: person)
let fields = representation.dictionary()                         // ["age": 30, "name": "Ana", ...]
let rebuilt = try CodableRepresentation.object(fields!).decode(as: Person.self)
let json = try representation.json                               // {"age":30,"name":"Ana"}, keys sorted
let same = try CodableRepresentation(data: representation.data)
```

JSON has no date or UUID, so `json` writes each typed value as `JSONEncoder` does by default: a date as
seconds since 2001, data as base64, a UUID as its `uuidString`, a decimal as a number, and a URL as its
`absoluteString`. Reading JSON back gives those plain values, and `decode(as:)` turns them back into the
typed ones, so a round trip through the type is exact. A decimal with more digits than a `Double` holds
loses them in JSON. A `Float` is held as the `double` its shortest form reads as, so `0.1` stays `0.1`.

```swift
let listing = try CodableRepresentation(json: text).decode(as: Listing.self)
let typed = try CodableRepresentation(encoding: listing)    // ["id": .uuid(…), "listed": .date(…), ...]
```

## Differences

`CodableDifference` lists what changed between two versions of any `Codable` value, shaped like
`CollectionDifference`. Each change has a `CodablePath` that reads as a string and a `CodableRepresentation` of
the value. A path is a collection of keys and indices, like `IndexPath`.

```swift
let difference = try CodableDifference(from: original, to: edited)
for change in difference { print(change) }   // ~ child.grandchildren[0]: "Ava" → "Eva"

if case .replace(path: "age", old: _, new: .integer(let age))? = difference.first { print(age) }
let rebuilt = try original.applying(difference)            // == edited
let undone = try edited.applying(difference.inverse())     // == original
let squashed = first.followed(by: second)                  // one difference from first's original to second's result
```

Objects compare key by key and arrays index by index, so an element inserted mid-array shows as
replacements of the ones after it. Sets compare member by member, so each change is one member added or
removed, at a path such as `tags{"swift"}`.

A difference is `Codable`, so it can be saved or sent to another device and applied there. It carries the
`CodableSchema` id of the type it was made from, and `applying(_:)` refuses one made for another schema.
Changes name their case, with paths as arrays and values as plain JSON:
`{"schemaID": "…", "changes": [{"replace": {"path": ["age"], "old": 30, "new": 31}}]}`.

## Mergeable

A type that merges with another version of itself implements two functions and gets six: the two
`merging` functions it writes, a mutating `merge` for each, and a static `merge` for each. A merge
always merges, with the favored side winning where both changed the same thing, and a type whose base is
itself merges with `@Merged(.mergeable(favoring:))`.

```swift
struct Tally: Mergeable {
    var count = 0
    func merging(with theirs: Tally, favoring side: MergeSide) throws -> Tally { side == .ours ? self : theirs }
    func merging(with theirs: Tally, from base: Tally, favoring side: MergeSide) throws -> Tally {
        Tally(count: count + theirs.count - base.count)
    }
}
```

## Schemas

`CodableSchema` reads the shape of a `Decodable` type from the type alone: each property's kind, which
are optional, which collections are sets, which values are dates, data, UUIDs, decimals or URLs, and every case of a `CaseIterable` enum. It's `Codable`, so two versions of a model can be compared with `CodableDifference`, and
`schema[change.path]` says whether a change is at an optional, an array or a dictionary.

```swift
let schema = try CodableSchema(Person.self)
print(schema)                       // {age: integer, child: {grandchildren: [string]}?, name: string}
schema["child.grandchildren[0]"]    // .string
```

A raw-value enum must be `CaseIterable`. A type that contains itself, an enum with associated values, or
an `init(from:)` that rejects placeholder values throws.

[Codable types](Sources/Merging/Tree/README.md) lists the full public surface of `CodableRepresentation`,
`CodableDifference` and `CodableSchema`.

## Requirements

Swift 6.1 (Xcode 16.3) or later. iOS 18, macOS 15, tvOS 18, watchOS 11 and
visionOS 2, or Linux. The macro builds with swift-syntax.

```swift
.package(url: "https://github.com/JonathanStorey/swift-merging.git", branch: "main")
```
