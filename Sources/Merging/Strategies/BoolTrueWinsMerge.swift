/// `true` if either side is. Merges with or without a base.
///
/// ```swift
/// @Merged(.trueWins) var flagged = false      // a flag anyone can set, such as "flagged" or "read"
/// ```
public struct BoolTrueWinsMerge: MergeStrategy {
    public init() {}

    public func merge(base: Bool, ours: Bool, theirs: Bool) -> Bool? { ours || theirs }

    public func merge(ours: Bool, theirs: Bool) -> Bool? { ours || theirs }
}
