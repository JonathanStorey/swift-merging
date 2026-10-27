/// A strategy that merges a property's `CodableTree`, its stored form, rather than its own type, so one
/// strategy suits many types. Give it an initializer on `Merged` that names the types it suits and calls
/// `init(wrappedValue:unchecked:)`.
public protocol TreeMergeStrategy: MergeStrategy where Value == CodableTree {}

extension TreeMergeStrategy {
    /// This strategy as a typed one, for values of `type`: they're encoded, merged as trees, and
    /// decoded. A result that doesn't decode is a conflict.
    ///
    /// ```swift
    /// try LargerTree().typed(as: Int.self).merge(base: 1, ours: 5, theirs: 3)    // 5
    /// ```
    public func typed<T: Codable & Sendable>(as type: T.Type) -> TypedMerge<Self, T> {
        TypedMerge()
    }
}

/// A tree strategy working on values of one type, made by `typed(as:)`.
public struct TypedMerge<Strategy: TreeMergeStrategy, Value: Codable & Sendable>: MergeStrategy {
    public init() {}

    public func merge(base: Value, ours: Value, theirs: Value) throws(MergeConflict<Value>) -> Value {
        do {
            let merged = try Strategy().merge(base: CodableTree(encoding: base), ours: CodableTree(encoding: ours), theirs: CodableTree(encoding: theirs))
            return try merged.decode(as: Value.self)
        } catch {
            throw MergeConflict(base: base, ours: ours, theirs: theirs)
        }
    }

    public func merge(ours: Value, theirs: Value) throws(MergeConflict<Value>) -> Value {
        do {
            let merged = try Strategy().merge(ours: CodableTree(encoding: ours), theirs: CodableTree(encoding: theirs))
            return try merged.decode(as: Value.self)
        } catch {
            throw MergeConflict(ours: ours, theirs: theirs)
        }
    }
}
