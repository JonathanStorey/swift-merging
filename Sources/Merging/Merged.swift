/// Picks the strategy one property of a `Codable` `Mergeable` type merges with. It encodes as its bare
/// value, so adding it doesn't change what's stored.
///
/// ```swift
/// struct Player: Codable, Mergeable {
///     var name = ""
///     @Merged(.maximum) var highScore = 0             // a standard strategy
///     @Merged(LongerMerge()) var title = ""           // a strategy of your own
/// }
/// ```
@propertyWrapper
public struct Merged<Value: Codable & Sendable, Strategy: MergeStrategy>: Sendable {
    public var wrappedValue: Value

    /// The wrapper itself, so `$` merges one property by its strategy:
    ///
    /// ```swift
    /// try player.$highScore.merge(with: theirs.highScore, from: base.highScore)
    /// ```
    public var projectedValue: Self {
        get { self }
        set { self = newValue }
    }

    /// Merges with a typed strategy, whose values are the property's.
    public init(wrappedValue: Value, _ strategy: Strategy) where Strategy.Value == Value {
        self.wrappedValue = wrappedValue
    }

    /// Merges with a strategy on the property's `CodableTree`, for any type. A tree strategy calls this
    /// from an initializer of its own that names the types it suits, so a mismatch doesn't compile.
    public init(wrappedValue: Value, unchecked strategy: Strategy) where Strategy: TreeMergeStrategy {
        self.wrappedValue = wrappedValue
    }
}

extension Merged {
    /// Merges with a shortcut, which a shortcut calls from an initializer of its own that names the types it
    /// suits.
    init(wrappedValue: Value, shortcut: Strategy) where Strategy: MergeShortcut {
        self.wrappedValue = wrappedValue
    }
}

extension Merged {
    /// Merges `theirs` into this property's value, which is ours, as the whole value's merge would: a side
    /// only one changed keeps that side, and the strategy decides when both did.
    public func merging(with theirs: Value, from base: Value) throws(MergeConflict<Value>) -> Value {
        do {
            return try decode(node(wrappedValue).merging(with: node(theirs), from: node(base)))
        } catch {
            throw MergeConflict(base: base, ours: wrappedValue, theirs: theirs)
        }
    }

    /// Merges `theirs` into this property's value without a common ancestor, if the strategy can.
    public func merging(with theirs: Value) throws(MergeConflict<Value>) -> Value {
        do {
            return try decode(node(wrappedValue).merging(with: node(theirs)))
        } catch {
            throw MergeConflict(ours: wrappedValue, theirs: theirs)
        }
    }

    /// Merges `theirs` into this property's value. On a conflict the value is left unchanged.
    public mutating func merge(with theirs: Value, from base: Value) throws(MergeConflict<Value>) {
        wrappedValue = try merging(with: theirs, from: base)
    }

    /// Merges `theirs` into this property's value without a common ancestor. On a conflict the value is left
    /// unchanged.
    public mutating func merge(with theirs: Value) throws(MergeConflict<Value>) {
        wrappedValue = try merging(with: theirs)
    }

    /// A value as it sits in a merge tree, under this property's rule.
    private func node(_ value: Value) throws -> MergeTree {
        .merged(try TreeEncoder().encode(value), mergeRule)
    }

    private func decode(_ tree: MergeTree) throws -> Value {
        try TreeDecoder().decode(Value.self, from: tree)
    }
}

extension Merged: Codable {
    public init(from decoder: any Decoder) throws {
        wrappedValue = try decoder.singleValueContainer().decode(Value.self)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(wrappedValue)
    }
}

extension Merged: Equatable where Value: Equatable {
    public static func == (lhs: Self, rhs: Self) -> Bool { lhs.wrappedValue == rhs.wrappedValue }
}

extension Merged: Hashable where Value: Hashable {
    public func hash(into hasher: inout Hasher) { hasher.combine(wrappedValue) }
}

extension Merged: MergeRuled {
    /// The strategy, made with `init()`, so it's the same whether the value was set or decoded. One of the
    /// initializers guarantees `Strategy.Value` is `Value` or `CodableTree`.
    var mergeRule: MergeRule {
        if let shortcut = Strategy.self as? any MergeShortcut.Type { return shortcut.rule(for: Value.self) }
        let strategy = Strategy()
        if Strategy.Value.self == CodableTree.self {
            return MergeRule { ours, theirs, base throws(MergeConflict<MergeTree>) in
                do {
                    let (mine, other) = (CodableTree(ours) as! Strategy.Value, CodableTree(theirs) as! Strategy.Value)
                    let merged = if let base {
                        try strategy.merge(base: CodableTree(base) as! Strategy.Value, ours: mine, theirs: other)
                    } else {
                        try strategy.merge(ours: mine, theirs: other)
                    }
                    return MergeTree(merged as! CodableTree)
                } catch {
                    throw MergeConflict(base: base, ours: ours, theirs: theirs)
                }
            }
        }
        return MergeRule(Value.self) { ours, theirs, base in
            let (mine, other) = (ours as! Strategy.Value, theirs as! Strategy.Value)
            let merged = if let base {
                try strategy.merge(base: base as! Strategy.Value, ours: mine, theirs: other)
            } else {
                try strategy.merge(ours: mine, theirs: other)
            }
            return merged as! Value
        }
    }
}
