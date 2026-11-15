/// A property's value with the strategy `@Merged` chose for it. `$name` returns one, so a property merges
/// on its own:
///
/// ```swift
/// struct Player {
///     @Merged(.keep(.ours)) var nickname = ""
/// }
///
/// let nickname = player.$nickname.merging(with: theirs.nickname, from: base.nickname)
/// ```
public struct MergedProperty<Value: Sendable>: Sendable {
    /// Ours.
    let value: Value
    let strategy: any MergeStrategy<Value>

    public init(_ value: Value, _ strategy: some MergeStrategy<Value>) {
        self.value = value
        self.strategy = strategy
    }

    /// Merges `theirs` into this value, which is ours, by the strategy. Without a `base` it's a two-way
    /// merge, which only a strategy that needs no ancestor can settle. `nil` if the versions can't be
    /// merged.
    public func merging(with theirs: Value, from base: Value?) -> Value? {
        strategyMerging(with: theirs, from: base)
    }

    private func strategyMerging(with theirs: Value, from base: Value?) -> Value? {
        guard let base else { return strategy.merge(ours: value, theirs: theirs) }
        return strategy.merge(base: base, ours: value, theirs: theirs)
    }
}

extension MergedProperty where Value: Equatable {
    /// Merges `theirs` into this value, which is ours. A side only one changed keeps that side, and the
    /// strategy decides when both did, even to the same value, since a counter both sides raised by 1 has
    /// gone up by 2. Without a `base` it's a two-way merge. `nil` if the versions can't be merged.
    public func merging(with theirs: Value, from base: Value?) -> Value? {
        if let base, value == base { return theirs }
        if let base, theirs == base { return value }
        return strategyMerging(with: theirs, from: base)
    }
}
