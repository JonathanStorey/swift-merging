import Foundation

/// Merges `Data` that holds a `Codable` value's JSON: it decodes all three versions, merges them node by
/// node as `.byNode` would, and encodes the result again. A version that won't decode is a conflict.
///
/// It's for a value kept as JSON rather than as itself, such as a SwiftData property stored as `Data`
/// to keep SwiftData from storing a struct as one column per field, which it can't do for an optional or
/// an enum inside the struct:
///
/// ```swift
/// @Merge(.json(Settings.self)) var settingsJSON = Data()
/// var settings: Settings {
///     get { JSONDataMerge<Settings>.decode(settingsJSON) ?? Settings() }
///     set { settingsJSON = JSONDataMerge<Settings>.encode(newValue) }
/// }
/// ```
///
/// Write the JSON with `encode(_:)`, which sorts keys, so equal values are equal bytes. Otherwise a
/// dictionary's order alone can make an unchanged value look changed.
public struct JSONDataMerge<Decoded: Codable & Sendable>: MergeStrategy {
    public typealias Value = Data

    public init() {}

    public func merge(base: Data, ours: Data, theirs: Data) -> Data? {
        guard let mine = Self.decode(ours), let other = Self.decode(theirs), let original = Self.decode(base) else { return nil }
        return CodableNodeMerge<Decoded>().merge(base: original, ours: mine, theirs: other).map(Self.encode)
    }

    public func merge(ours: Data, theirs: Data) -> Data? {
        if ours == theirs { return ours }
        guard let mine = Self.decode(ours), let other = Self.decode(theirs) else { return nil }
        return CodableNodeMerge<Decoded>().merge(ours: mine, theirs: other).map(Self.encode)
    }

    /// A value's JSON, with sorted keys so equal values are equal bytes.
    public static func encode(_ value: Decoded) -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return (try? encoder.encode(value)) ?? Data()
    }

    /// The value in `data`, or `nil` if it doesn't hold one.
    public static func decode(_ data: Data) -> Decoded? {
        try? JSONDecoder().decode(Decoded.self, from: data)
    }
}

extension MergeStrategy {
    /// Merges `Data` holding `type`'s JSON node by node.
    public static func json<Decoded>(_ type: Decoded.Type) -> Self where Self == JSONDataMerge<Decoded> {
        Self()
    }
}
