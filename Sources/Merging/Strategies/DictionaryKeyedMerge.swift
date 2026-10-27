/// Merges a dictionary key by key, whatever the key's type: a key only one side changed, added, or removed
/// keeps that side, and a key both sides changed merges its values by their shape, honoring any strategies
/// inside them. It takes any `Codable` type built from a dictionary literal, such as `Dictionary` or an
/// ordered dictionary.
///
/// ```swift
/// @Merged(.byKey) var pins: [Spot: String] = [:]
/// ```
public struct DictionaryKeyedMerge<Value: ExpressibleByDictionaryLiteral & Codable & Sendable>: MergeStrategy {
    public init() {}

    public func merge(base: Value, ours: Value, theirs: Value) throws(MergeConflict<Value>) -> Value {
        try mergeByKey(base: base, ours: ours, theirs: theirs)
    }

    public func merge(ours: Value, theirs: Value) throws(MergeConflict<Value>) -> Value {
        try mergeByKey(base: nil, ours: ours, theirs: theirs)
    }

    private func mergeByKey(base: Value?, ours: Value, theirs: Value) throws(MergeConflict<Value>) -> Value {
        /// The dictionary's merge tree, keeping the rules of the values inside.
        func tree(_ value: Value) throws -> MergeTree {
            let tree = try TreeEncoder().encode(value)
            guard case .merged(let data, _) = tree else { return tree }
            return data
        }
        do {
            let merged = try MergeTree.mergeDictionaries(tree(ours), tree(theirs), base: base.map(tree))
            return try TreeDecoder().decode(Value.self, from: merged)
        } catch {
            throw MergeConflict(base: base, ours: ours, theirs: theirs)
        }
    }
}

/// The shortcut for `DictionaryKeyedMerge`, as `.byKey`. It merges the merge tree as the typed strategy does.
public struct ByKeyShortcut: MergeStrategy, MergeShortcut {
    public typealias Value = Never

    public init() {}

    public func merge(base: Never, ours: Never, theirs: Never) -> Never {}

    static func rule<Value: Codable & Sendable>(for type: Value.Type) -> MergeRule {
        MergeRule { ours, theirs, base throws(MergeConflict<MergeTree>) in try MergeTree.mergeDictionaries(ours, theirs, base: base) }
    }
}

extension MergeStrategy where Self == ByKeyShortcut {
    /// Merges a dictionary key by key.
    public static var byKey: ByKeyShortcut { ByKeyShortcut() }
}

extension Merged where Strategy == ByKeyShortcut {
    public init(wrappedValue: Value, _ strategy: ByKeyShortcut) where Value: ExpressibleByDictionaryLiteral {
        self.init(wrappedValue: wrappedValue, shortcut: strategy)
    }
}

/// Every dictionary merges by key. One with string or integer keys encodes as an object, which merges by
/// key anyway. Any other encodes as a flat array of keys and values, which would mangle in an array merge.
/// Merging the merge tree rather than a `CodableTree` keeps the rules of the values inside.
extension Dictionary: DefaultMergeRule {
    static var defaultMergeRule: MergeRule {
        MergeRule { ours, theirs, base throws(MergeConflict<MergeTree>) in try MergeTree.mergeDictionaries(ours, theirs, base: base) }
    }
}

extension MergeTree {
    static func mergeDictionaries(_ ours: MergeTree, _ theirs: MergeTree, base: MergeTree?) throws(MergeConflict<MergeTree>) -> MergeTree {
        guard case .array = ours else {
            if let base { return try ours.merging(with: theirs, from: base) }
            return try ours.merging(with: theirs)
        }
        // Keys line up by their canonical text, so any key works.
        var keys: [String: MergeTree] = [:]
        func object(_ tree: MergeTree) throws(MergeConflict<MergeTree>) -> MergeTree {
            guard case .array(let flat) = tree, flat.count.isMultiple(of: 2) else { throw MergeConflict(ours: tree, theirs: tree) }
            var object: [String: MergeTree] = [:]
            for index in stride(from: 0, to: flat.count, by: 2) {
                let text = flat[index].canonical
                keys[text] = flat[index]
                object[text] = flat[index + 1]
            }
            return .object(object)
        }
        let (mine, other) = (try object(ours), try object(theirs))
        let merged = if let base { try mine.merging(with: other, from: object(base)) } else { try mine.merging(with: other) }
        guard case .object(let entries) = merged else { return ours }
        return .array(entries.flatMap { [keys[$0.key]!, $0.value] })
    }
}
