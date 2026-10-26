// What `@Mergeable` expansions call for each property. Overloads pick the merge from the property's type,
// so the macro needn't know it: a `Mergeable` type's own merge, else keeping the side that changed.

/// Keeps the side that changed. Without a base, equal values merge and different ones conflict.
public func _mergeProperty<T: Equatable & Sendable>(base: T?, ours: T, theirs: T) throws(MergeConflict<T>) -> T {
    if ours == theirs { return ours }
    if let base {
        if theirs == base { return ours }
        if ours == base { return theirs }
    }
    throw MergeConflict(base: base, ours: ours, theirs: theirs)
}

public func _mergeProperty<T: Mergeable>(base: T?, ours: T, theirs: T) throws(MergeConflict<T>) -> T {
    try ours.merging(theirs, base: base)
}

/// A type that's both uses its own merge.
public func _mergeProperty<T: Mergeable & Equatable>(base: T?, ours: T, theirs: T) throws(MergeConflict<T>) -> T {
    try ours.merging(theirs, base: base)
}

public func _mergeProperty<S: MergeStrategy>(
    base: S.Value?, ours: S.Value, theirs: S.Value, with strategy: S
) throws(MergeConflict<S.Value>) -> S.Value {
    guard let base else { return try strategy.merge(ours: ours, theirs: theirs) }
    return try strategy.merge(base: base, ours: ours, theirs: theirs)
}
