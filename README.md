# Merging

Strategies for merging two or three versions of a value, for sync engines and editors that meet the
same record changed in two places.

```swift
import Merging

@Mergeable
struct Note {
    var title = ""                                  // keeps the side that changed
    var address = Address()                         // merges by Address's own merge
    @Merged(MaxMerge<Int>()) var highScore = 0
}

let merged = try Note.merge(base: original, ours: mine, theirs: yours)
```

`Mergeable` is the main protocol: a type merges with `merge(ours:theirs:)`, and `merge(base:ours:theirs:)`
uses it unless the type writes its own. A merge throws a `MergeConflict` holding the versions when it
can't merge them.

`@Mergeable` writes both for a struct, one stored `var` at a time:

- `@Merged(_:)` picks a property's `MergeStrategy`, for a type that merges differently in different
  places, such as an `Int` that's a counter in one property and a high score in another.
- Otherwise a `Mergeable` property merges by its type's own merge.
- Otherwise an `Equatable` property keeps the side that changed, and conflicts if both changed it.

A conflict in any property makes the whole value a conflict. To decide those yourself, write your own
`merge` and call the generated `mergeProperties(base:ours:theirs:)` first.

A generic strategy names its value type in `@Merged`, as in `MaxMerge<Int>()`, because a macro's
argument is type-checked on its own, without the property's type.

## Requirements

Swift 6.0 or later, for typed throws and Swift Testing. iOS 17, macOS 14, tvOS 17, watchOS 10 and
visionOS 1, or Linux.

```swift
.package(url: "https://github.com/JonathanStorey/swift-merging.git", branch: "main")
```
