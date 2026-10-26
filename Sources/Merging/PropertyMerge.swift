// What `@Mergeable` expansions call for each property. Overloads pick the merge from the property's type,
// so the macro needn't know it: a `Mergeable` type's own merge, else keeping the side that changed.

/// Equal values merge, and different ones conflict.
public func _mergeProperty<T: Equatable & Sendable>(ours: T, theirs: T) throws(MergeConflict<T>) -> T {
    if ours == theirs { return ours }
    throw MergeConflict(ours: ours, theirs: theirs)
}

/// Keeps the side that changed.
public func _mergeProperty<T: Equatable & Sendable>(base: T, ours: T, theirs: T) throws(MergeConflict<T>) -> T {
    if ours == theirs || theirs == base { return ours }
    if ours == base { return theirs }
    throw MergeConflict(base: base, ours: ours, theirs: theirs)
}

public func _mergeProperty<T: Mergeable>(ours: T, theirs: T) throws(MergeConflict<T>) -> T {
    try ours.merging(theirs)
}

public func _mergeProperty<T: Mergeable>(base: T, ours: T, theirs: T) throws(MergeConflict<T>) -> T {
    try ours.merging(theirs, base: base)
}

/// A type that's both uses its own merge.
public func _mergeProperty<T: Mergeable & Equatable>(ours: T, theirs: T) throws(MergeConflict<T>) -> T {
    try ours.merging(theirs)
}

public func _mergeProperty<T: Mergeable & Equatable>(base: T, ours: T, theirs: T) throws(MergeConflict<T>) -> T {
    try ours.merging(theirs, base: base)
}

public func _mergeProperty<S: MergeStrategy>(ours: S.Value, theirs: S.Value, with strategy: S) throws(MergeConflict<S.Value>) -> S.Value {
    try strategy.merge(ours: ours, theirs: theirs)
}

public func _mergeProperty<S: MergeStrategy>(
    base: S.Value, ours: S.Value, theirs: S.Value, with strategy: S
) throws(MergeConflict<S.Value>) -> S.Value {
    try strategy.merge(base: base, ours: ours, theirs: theirs)
}
