/// Picks the strategy one property of a `Codable` `Mergeable` type merges with. It encodes as its bare
/// value, so adding it doesn't change what's stored.
///
/// ```swift
/// struct Player: Codable, Mergeable {
///     var name = ""
///     @Merged(MaxMerge()) var highScore = 0
/// }
/// ```
@propertyWrapper
public struct Merged<Strategy: MergeStrategy>: Sendable where Strategy.Value: Codable {
    public var wrappedValue: Strategy.Value
    public let strategy: Strategy

    public init(wrappedValue: Strategy.Value, _ strategy: Strategy) {
        self.wrappedValue = wrappedValue
        self.strategy = strategy
    }
}

extension Merged: Codable {
    public init(from decoder: any Decoder) throws {
        wrappedValue = try decoder.singleValueContainer().decode(Strategy.Value.self)
        strategy = Strategy()
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(wrappedValue)
    }
}

extension Merged: Equatable where Strategy.Value: Equatable {
    public static func == (lhs: Self, rhs: Self) -> Bool { lhs.wrappedValue == rhs.wrappedValue }
}

extension Merged: Hashable where Strategy.Value: Hashable {
    public func hash(into hasher: inout Hasher) { hasher.combine(wrappedValue) }
}

extension Merged: MergeRuled {
    var mergeRule: MergeRule {
        let strategy = strategy
        return MergeRule(Strategy.Value.self) { ours, theirs, base throws(MergeConflict<Strategy.Value>) in
            if let base { try strategy.merge(base: base, ours: ours, theirs: theirs) } else { try strategy.merge(ours: ours, theirs: theirs) }
        }
    }
}
