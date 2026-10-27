/// Stands in for a generic typed strategy in `@Merged`, so its shorthand needs no parentheses. A static
/// property can't be generic, so `.maximum` names a shortcut instead of `ComparableMaximumMerge<Value>`. The
/// shortcut's own `@Merged` initializer checks the property's type, and its rule opens the property's value
/// as the strategy's constraint to merge it the same way the typed strategy does.
protocol MergeShortcut {
    static func rule<Value: Codable & Sendable>(for type: Value.Type) -> MergeRule
}

/// Theirs and the base cast to the type a shortcut opened ours as.
func opened<Opened>(_ ours: Opened, _ theirs: Any, _ base: Any?) throws -> (theirs: Opened, base: Opened?) {
    guard let theirs = theirs as? Opened else { throw ShortcutMismatch() }
    guard let base else { return (theirs, nil) }
    guard let base = base as? Opened else { throw ShortcutMismatch() }
    return (theirs, base)
}

/// A value that isn't the type its shortcut's initializer allowed, which they rule out.
struct ShortcutMismatch: Error {}
