/// Merges a collection element by element, like a three-way merge of lines: an element either side
/// removed is removed, and what each side inserted goes where it was inserted, ours first. Elements match by
/// `==`, so an element both sides replaced is a conflict unless they replaced it alike. A `String` merges
/// character by character. Needs a base, and without one only equal collections merge.
///
/// ```swift
/// @Merged(.byElement) var steps: [Step] = []
/// ```
public struct RangeReplaceableCollectionElementMerge<Value: RangeReplaceableCollection & Sendable>: MergeStrategy
where Value.Element: Equatable {
    public init() {}

    public func merge(base: Value, ours: Value, theirs: Value) throws(MergeConflict<Value>) -> Value {
        do {
            let merged = try mergeElements(Array(ours), Array(theirs), base: Array(base)) { ours, theirs, _ throws(ElementConflict) in
                guard ours == theirs else { throw ElementConflict() }
                return ours
            } conflict: { _, _, _ in
                ElementConflict()
            }
            return Value(merged)
        } catch {
            throw MergeConflict(base: base, ours: ours, theirs: theirs)
        }
    }

    public func merge(ours: Value, theirs: Value) throws(MergeConflict<Value>) -> Value {
        guard ours.elementsEqual(theirs) else { throw MergeConflict(ours: ours, theirs: theirs) }
        return ours
    }
}

private struct ElementConflict: Error {}

/// The shortcut for `RangeReplaceableCollectionElementMerge`, as `.byElement`. It merges the merge tree, so
/// an element both sides replaced merges by its own merge, and the elements need no `==`. Text merges
/// character by character.
public struct ByElementShortcut: MergeStrategy, MergeShortcut {
    public typealias Value = Never

    public init() {}

    public func merge(base: Never, ours: Never, theirs: Never) -> Never {}

    static func rule<Value: Codable & Sendable>(for type: Value.Type) -> MergeRule {
        MergeRule { ours, theirs, base throws(MergeConflict<MergeTree>) in
            guard case .string = ours else {
                guard let base else { return try ours.merging(with: theirs) }
                return try ours.merging(with: theirs, from: base)
            }
            let merged = if let base {
                try characters(ours).merging(with: characters(theirs), from: characters(base))
            } else {
                try characters(ours).merging(with: characters(theirs))
            }
            guard case .array(let elements) = merged else { return merged }
            return .string(elements.map { if case .string(let character) = $0 { character } else { "" } }.joined())
        }
    }

    /// Text as an array of its characters, and anything else as it is.
    private static func characters(_ tree: MergeTree) -> MergeTree {
        guard case .string(let text) = tree else { return tree }
        return .array(text.map { .string(String($0)) })
    }
}

extension MergeStrategy where Self == ByElementShortcut {
    /// Merges a list element by element, keeping both sides' insertions, or text character by character.
    public static var byElement: ByElementShortcut { ByElementShortcut() }
}

extension Merged where Strategy == ByElementShortcut {
    public init(wrappedValue: Value, _ strategy: ByElementShortcut) where Value: RangeReplaceableCollection {
        self.init(wrappedValue: wrappedValue, shortcut: strategy)
    }
}
