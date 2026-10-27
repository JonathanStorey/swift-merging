/// `true` if either side is. Merges with or without a base.
///
/// ```swift
/// @Merged(.trueWins) var flagged = false
/// ```
public struct BoolTrueWinsMerge: MergeStrategy {
    public typealias Value = Bool

    public init() {}

    public func merge(base: Bool, ours: Bool, theirs: Bool) -> Bool { ours || theirs }

    public func merge(ours: Bool, theirs: Bool) -> Bool { ours || theirs }
}

extension MergeStrategy where Self == BoolTrueWinsMerge {
    /// A flag anyone can set, such as "flagged" or "read".
    public static var trueWins: BoolTrueWinsMerge { BoolTrueWinsMerge() }
}
