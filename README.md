# Merging

Strategies for merging two or three versions of a value, for sync engines and editors that meet the
same record changed in two places.

```swift
import Merging

let merged = try ThreeWayMerge<String>().merge(base: "Draft", ours: "Edited", theirs: "Draft")   // "Edited"
```

A strategy conforms to `MergeStrategy`. It implements the two-way `merge(ours:theirs:)`, which the
three-way `merge(base:ours:theirs:)` uses by default, and throws a `MergeConflict` when the versions can't
be merged. A type can name how its values merge by conforming to `Mergeable`, and `@Merged(_:)` picks the
strategy for one stored property.

## Requirements

Swift 6.0 or later, for typed throws and Swift Testing. iOS 17, macOS 14, tvOS 17, watchOS 10 and
visionOS 1, or Linux.

```swift
.package(url: "https://github.com/JonathanStorey/swift-merging.git", branch: "main")
```
