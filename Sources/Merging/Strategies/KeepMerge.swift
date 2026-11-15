/// A side of a merge, which `.keep` names.
public enum MergeSide: Sendable {
    case ours
    case theirs
}

/// Always keeps one side when both sides changed the value. Merges with or without a base.
///
/// ```swift
/// @Merged(.keep(.ours)) var draft = ""            // a draft only this device should finish
/// @Merged(.keep(.theirs)) var cachedTotal = 0     // a value the other side recomputed
/// ```
public struct KeepMerge<Value: Sendable>: MergeStrategy {
    let side: MergeSide

    public init(_ side: MergeSide) {
        self.side = side
    }

    public func merge(base: Value, ours: Value, theirs: Value) -> Value? {
        merge(ours: ours, theirs: theirs)
    }

    public func merge(ours: Value, theirs: Value) -> Value? {
        side == .ours ? ours : theirs
    }
}
