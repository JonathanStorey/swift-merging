/// Picks the strategy one property of a `Codable` `Mergeable` type merges with. It encodes as its bare
/// value, so adding it doesn't change what's stored.
///
/// ```swift
/// struct Player: Codable, Mergeable {
///     var name = ""
///     @Merged(.maximum) var highScore = 0                 // a standard strategy, on the stored form
///     @Merged(LongerMerge()) var title = ""           // a typed strategy, on the property's own type
/// }
/// ```
@propertyWrapper
public struct Merged<Value: Codable & Sendable, Strategy: MergeStrategy>: Sendable {
    public var wrappedValue: Value

    /// Merges with a typed strategy, whose values are the property's.
    public init(wrappedValue: Value, _ strategy: Strategy) where Strategy.Value == Value {
        self.wrappedValue = wrappedValue
    }

    /// Merges with a strategy on the property's `Snapshot`, such as `.maximum`.
    public init(wrappedValue: Value, _ strategy: Strategy) where Strategy.Value == Snapshot {
        self.wrappedValue = wrappedValue
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
    /// initializers guarantees `Strategy.Value` is `Value` or `Snapshot`.
    var mergeRule: MergeRule {
        let strategy = Strategy()
        if Strategy.Value.self == Snapshot.self {
            return MergeRule { ours, theirs, base throws(MergeConflict<MergeTree>) in
                do {
                    let (mine, other) = (Snapshot(ours) as! Strategy.Value, Snapshot(theirs) as! Strategy.Value)
                    let merged = if let base {
                        try strategy.merge(base: Snapshot(base) as! Strategy.Value, ours: mine, theirs: other)
                    } else {
                        try strategy.merge(ours: mine, theirs: other)
                    }
                    return MergeTree(merged as! Snapshot)
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
