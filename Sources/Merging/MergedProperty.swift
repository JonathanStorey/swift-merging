/// A property's value with the strategy `@Merged` chose for it. `$name` returns one, so a property merges
/// on its own, and `$name` writes a mutating `merge` back to the property:
///
/// ```swift
/// struct Player {
///     @Merged(.keep(.ours)) var nickname = ""
/// }
///
/// let nickname = player.$nickname.merging(with: theirs.nickname, from: base.nickname)
/// player.$nickname.merge(with: theirs.nickname, from: base.nickname)
/// ```
public struct MergedProperty<Value: Sendable>: Sendable {
    /// Ours: the property's value, and the merged value after `merge`.
    public private(set) var value: Value
    let strategy: any MergeStrategy<Value>
    /// Equality for an `Equatable` value, which lets a three-way merge keep a side only one changed.
    let isEqual: (@Sendable (Value, Value) -> Bool)?

    private init(value: Value, strategy: any MergeStrategy<Value>, isEqual: (@Sendable (Value, Value) -> Bool)?) {
        self.value = value
        self.strategy = strategy
        self.isEqual = isEqual
    }

    /// A value that isn't `Equatable`, whose strategy decides every merge.
    public init(_ value: Value, _ strategy: some MergeStrategy<Value>) {
        self.init(value: value, strategy: strategy, isEqual: nil)
    }
}

extension MergedProperty where Value: Equatable {
    /// An `Equatable` value, whose three-way merge keeps a side only one changed.
    public init(_ value: Value, _ strategy: some MergeStrategy<Value>) {
        self.init(value: value, strategy: strategy, isEqual: { $0 == $1 })
    }
}

extension MergedProperty {
    /// Merges `theirs` into this value, which is ours, knowing their common ancestor. For an `Equatable`
    /// value, a side only one changed keeps that side, and the strategy decides when both did, even to the
    /// same value, since a counter both sides raised by 1 has gone up by 2. For any other value, the
    /// strategy decides. `nil` if the versions can't be merged.
    public func merging(with theirs: Value, from base: Value) -> Value? {
        if let isEqual {
            if isEqual(value, base) { return theirs }
            if isEqual(theirs, base) { return value }
        }
        return strategy.merge(base: base, ours: value, theirs: theirs)
    }

    /// Merges `theirs` into this value without a common ancestor, which only a strategy that needs no base
    /// can settle. `nil` if the versions can't be merged without one.
    public func merging(with theirs: Value) -> Value? {
        strategy.merge(ours: value, theirs: theirs)
    }

    /// Merges `theirs` into this value, knowing their common ancestor, and returns whether it could. If it
    /// couldn't, the value is left unchanged.
    @discardableResult
    public mutating func merge(with theirs: Value, from base: Value) -> Bool {
        guard let merged = merging(with: theirs, from: base) else { return false }
        value = merged
        return true
    }

    /// Merges `theirs` into this value without a common ancestor, and returns whether it could. If it
    /// couldn't, the value is left unchanged.
    @discardableResult
    public mutating func merge(with theirs: Value) -> Bool {
        guard let merged = merging(with: theirs) else { return false }
        value = merged
        return true
    }
}
