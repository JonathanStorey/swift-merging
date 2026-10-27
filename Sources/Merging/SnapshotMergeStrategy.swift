/// A strategy that merges a property's `Snapshot`, its stored form, rather than its own type. The standard
/// strategies, such as `.maximum`, are snapshot strategies.
public protocol SnapshotMergeStrategy: MergeStrategy where Value == Snapshot {}

extension SnapshotMergeStrategy {
    /// This strategy as a typed one, for values of `type`: they're encoded, merged as snapshots, and
    /// decoded. A result that doesn't decode is a conflict.
    ///
    /// ```swift
    /// try MaxMerge().typed(as: Int.self).merge(base: 1, ours: 5, theirs: 3)    // 5
    /// ```
    public func typed<T: Codable & Sendable>(as type: T.Type) -> TypedMerge<Self, T> {
        TypedMerge()
    }
}

/// A snapshot strategy working on values of one type, made by `typed(as:)`.
public struct TypedMerge<Strategy: SnapshotMergeStrategy, Value: Codable & Sendable>: MergeStrategy {
    public init() {}

    public func merge(base: Value, ours: Value, theirs: Value) throws(MergeConflict<Value>) -> Value {
        do {
            let merged = try Strategy().merge(base: Snapshot(encoding: base), ours: Snapshot(encoding: ours), theirs: Snapshot(encoding: theirs))
            return try merged.decode(as: Value.self)
        } catch {
            throw MergeConflict(base: base, ours: ours, theirs: theirs)
        }
    }

    public func merge(ours: Value, theirs: Value) throws(MergeConflict<Value>) -> Value {
        do {
            let merged = try Strategy().merge(ours: Snapshot(encoding: ours), theirs: Snapshot(encoding: theirs))
            return try merged.decode(as: Value.self)
        } catch {
            throw MergeConflict(ours: ours, theirs: theirs)
        }
    }
}
