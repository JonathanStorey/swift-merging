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

> **Being rewritten.** Merging is moving to property-level merging with the `@Merged` macro, which works
> the same on a struct, a class, or a SwiftData `@Model`. The strategies of 0.3.0 are being ported one at a
> time and sit in `Sources/Merging/Unported` until they are. Use the `0.3.0` tag for the property wrapper
> and whole-value merging.

## @Merged

`@Merged(strategy)` marks a stored property and writes `$name`, a `MergedProperty` of the property's value
and its strategy. The property itself is left as written, so it stores, encodes, and compares exactly as it
would without the macro.

```swift
public func merging(with theirs: Value, from base: Value) -> Value?    // three-way
public func merging(with theirs: Value) -> Value?                      // two-way
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
| `.keep(.ours)`, `.keep(.theirs)` | `KeepMerge` | anything | the named side | no |

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

## Requirements

Swift 6.1 (Xcode 16.3) or later. iOS 17, macOS 14, tvOS 17, watchOS 10 and
visionOS 1, or Linux. The macro builds with swift-syntax.

```swift
.package(url: "https://github.com/JonathanStorey/swift-merging.git", branch: "main")
```
