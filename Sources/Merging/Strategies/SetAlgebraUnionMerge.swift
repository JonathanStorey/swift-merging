/// Merges a set so that no addition is lost. With a base, it merges by membership, keeping what either side
/// added and dropping what either removed. Without one, there's no telling an addition from a removal, so it
/// keeps every element either side has.
///
/// ```swift
/// @Merged(.union) var recipients: Set<String> = []
/// ```
public struct SetAlgebraUnionMerge<Value: SetAlgebra & Sendable>: MergeStrategy {
    public init() {}

    public func merge(base: Value, ours: Value, theirs: Value) -> Value {
        SetAlgebraMembershipMerge().merge(base: base, ours: ours, theirs: theirs)
    }

    public func merge(ours: Value, theirs: Value) -> Value { ours.union(theirs) }
}

/// The shortcut for `SetAlgebraUnionMerge`, as `.union`.
public struct UnionShortcut: MergeStrategy, MergeShortcut {
    public typealias Value = Never

    public init() {}

    public func merge(base: Never, ours: Never, theirs: Never) -> Never {}

    static func rule<Value: Codable & Sendable>(for type: Value.Type) -> MergeRule {
        MergeRule(type) { ours, theirs, base in
            guard let ours = ours as? any SetAlgebra, let merged = try open(ours, theirs, base) as? Value else {
                throw ShortcutMismatch()
            }
            return merged
        }
    }

    private static func open<Opened: SetAlgebra>(_ ours: Opened, _ theirs: Any, _ base: Any?) throws -> Opened {
        let (theirs, base) = try opened(ours, theirs, base)
        guard let base else { return ours.union(theirs) }
        return .mergedByMembership(base: base, ours: ours, theirs: theirs)
    }
}

extension MergeStrategy where Self == UnionShortcut {
    /// Keeps every addition, such as tags or recipients. Merges without a base too.
    public static var union: UnionShortcut { UnionShortcut() }
}

extension Merged where Strategy == UnionShortcut {
    public init(wrappedValue: Value, _ strategy: UnionShortcut) where Value: SetAlgebra {
        self.init(wrappedValue: wrappedValue, shortcut: strategy)
    }
}
