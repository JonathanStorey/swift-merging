/// Merges a dictionary key by key, whatever the key's type: a key only one side changed, added, or removed
/// keeps that side, and a key both sides changed merges only if they changed it alike. Needs a base.
///
/// ```swift
/// @Merged(.byKey) var pins: [Spot: String] = [:]
/// ```
public struct DictionaryKeyedMerge<Key: Hashable & Sendable, Element: Equatable & Sendable>: MergeStrategy {
    public typealias Value = [Key: Element]

    public init() {}

    public func merge(base: [Key: Element], ours: [Key: Element], theirs: [Key: Element]) -> [Key: Element]? {
        var merged: [Key: Element] = [:]
        for key in Set(base.keys).union(ours.keys).union(theirs.keys) {
            let (original, mine, other) = (base[key], ours[key], theirs[key])
            let value: Element?
            if mine == original {
                value = other
            } else if other == original || mine == other {
                value = mine
            } else {
                return nil
            }
            merged[key] = value
        }
        return merged
    }
}
