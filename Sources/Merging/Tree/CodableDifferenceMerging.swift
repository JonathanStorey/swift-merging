import Foundation

/// Differences made from the same value merge into one difference with both sides' changes. Where both
/// changed the same place, the favored side's changes win.
///
/// ```swift
/// let both = try mine.merging(with: yours, favoring: .theirs)
/// let both = try mine.merging(with: yours, from: original, favoring: .ours)   // sets merge by membership
/// ```
extension CodableDifference: Mergeable {
    public typealias MergeBase = CodableRepresentation

    /// Both differences' changes, path by path. A change of the other side's is left out where it clashes
    /// with one of the favored side's: the same path changed differently, one path inside the other, or
    /// both sides growing or shrinking the same array.
    public func merging(with theirs: CodableDifference, favoring side: MergeSide) throws -> CodableDifference {
        let schemaID = try matchingSchemaID(theirs)
        let (favored, other) = side == .ours ? (changes, theirs.changes) : (theirs.changes, changes)
        var merged = favored
        for change in other where !favored.contains(where: { $0 == change || $0.clashes(with: change) }) {
            merged.append(change)
        }
        return CodableDifference(merged.sorted { $0.path.precedes($1.path) }, schemaID: schemaID)
    }

    /// Both differences applied to `base` and merged as `CodableTotalMerge` does. A `CodableRepresentation` doesn't
    /// know which arrays are sets, so a set merges by position here. The overload that takes the typed
    /// value merges it by membership.
    public func merging(with theirs: CodableDifference, from base: CodableRepresentation, favoring side: MergeSide) throws -> CodableDifference {
        let schemaID = try matchingSchemaID(theirs)
        var ours = base
        ours.apply(self)
        var others = base
        others.apply(theirs)
        let merged = try MergeTree(ours).merging(with: MergeTree(others), from: MergeTree(base), favoring: side)
        return CodableDifference(CodableRepresentation(merged).difference(from: base).changes, schemaID: schemaID)
    }

    /// Both differences applied to `base` and merged by `CodableTotalMerge`, so sets merge by membership and
    /// dictionaries by key. Throws if either doesn't apply to `base`.
    public func merging<Value: Codable & Sendable>(with theirs: CodableDifference, from base: Value, favoring side: MergeSide) throws -> CodableDifference {
        let ours = try base.applying(self)
        let others = try base.applying(theirs)
        let merged = CodableTotalMerge<Value>(favoring: side).merge(base: base, ours: ours, theirs: others) ?? (side == .ours ? ours : others)
        return try CodableDifference(from: base, to: merged)
    }

    /// Merges `theirs` into this difference, applying both to `base` and merging by `CodableTotalMerge`.
    public mutating func merge<Value: Codable & Sendable>(with theirs: CodableDifference, from base: Value, favoring side: MergeSide) throws {
        self = try merging(with: theirs, from: base, favoring: side)
    }

    /// The schema id both differences share, or the one that has one. Throws if they were made for
    /// different schemas.
    private func matchingSchemaID(_ other: CodableDifference) throws -> UUID? {
        if let schemaID, let otherID = other.schemaID, schemaID != otherID {
            let reason = "The differences were made for different schemas, \(schemaID) and \(otherID)."
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: reason))
        }
        return schemaID ?? other.schemaID
    }
}

extension CodableDifference {
    /// This difference, then `next`, as one difference from this one's original to `next`'s result. `nil`
    /// if `next` wasn't made from this one's result: it was made for another schema, or it changes a place
    /// in a way this one's result rules out, such as removing what this one removed.
    ///
    /// ```swift
    /// let squashed = first.followed(by: second)   // as if made from the first original to the last result
    /// ```
    public func followed(by next: CodableDifference) -> CodableDifference? {
        if let schemaID, let nextID = next.schemaID, schemaID != nextID { return nil }
        var result = changes
        for change in next.changes {
            if let index = result.firstIndex(where: { $0.path == change.path }) {
                guard let combined = result[index].followed(by: change) else { return nil }
                if let combined { result[index] = combined } else { result.remove(at: index) }
            } else if let index = result.firstIndex(where: { $0.path.contains(change.path) }) {
                // A change inside a value this difference inserted or replaced edits that value.
                guard var element = result[index].newElement else { return nil }
                element.apply(CodableDifference([change.relative(to: result[index].path)]))
                result[index] = result[index].with(newElement: element)
            } else if result.contains(where: { change.path.contains($0.path) }) {
                // A change around values this difference changed: its old value is what this one left.
                guard var old = change.oldElement else { return nil }
                let inner = result.filter { change.path.contains($0.path) }
                old.apply(CodableDifference(inner.map { $0.relative(to: change.path) }).inverse())
                result.removeAll { change.path.contains($0.path) }
                let adjusted = change.with(oldElement: old)
                if case .replace(_, let old, let new) = adjusted, old == new { continue }
                result.append(adjusted)
            } else {
                result.append(change)
            }
        }
        return CodableDifference(result.sorted { $0.path.precedes($1.path) }, schemaID: schemaID ?? next.schemaID)
    }
}

private extension CodableDifference.Change {
    /// An insertion or removal of an array element, which changes the array's length.
    var isStructural: Bool {
        guard case .index? = path.components.last else { return false }
        if case .replace = self { return false }
        return true
    }

    /// Whether this change and `other`, made from the same original, can't both apply.
    func clashes(with other: Self) -> Bool {
        if path == other.path { return self != other }
        if path.contains(other.path) || other.path.contains(path) { return true }
        return isStructural && other.isStructural && path.components.dropLast() == other.path.components.dropLast()
    }

    /// This change followed by `next` at the same path: the combined change, `.some(nil)` where they cancel
    /// out, or `nil` where `next` couldn't follow this one.
    func followed(by next: Self) -> Self?? {
        switch (self, next) {
        case let (.insert(path, _), .replace(_, _, new)): .some(.insert(path: path, element: new))
        case (.insert, .remove): .some(nil)
        case let (.replace(path, old, _), .replace(_, _, new)): .some(old == new ? nil : .replace(path: path, old: old, new: new))
        case let (.replace(path, old, _), .remove): .some(.remove(path: path, element: old))
        case let (.remove(path, old), .insert(_, new)): .some(old == new ? nil : .replace(path: path, old: old, new: new))
        default: nil
        }
    }

    /// The value at the path after this change, if there is one.
    var newElement: CodableRepresentation? {
        switch self {
        case .insert(_, let element), .replace(_, _, let element): element
        case .remove: nil
        }
    }

    /// The value at the path before this change, if there was one.
    var oldElement: CodableRepresentation? {
        switch self {
        case .remove(_, let element), .replace(_, let element, _): element
        case .insert: nil
        }
    }

    func with(newElement: CodableRepresentation) -> Self {
        switch self {
        case .insert(let path, _): .insert(path: path, element: newElement)
        case .replace(let path, let old, _): .replace(path: path, old: old, new: newElement)
        case .remove: self
        }
    }

    func with(oldElement: CodableRepresentation) -> Self {
        switch self {
        case .remove(let path, _): .remove(path: path, element: oldElement)
        case .replace(let path, _, let new): .replace(path: path, old: oldElement, new: new)
        case .insert: self
        }
    }

    /// This change with its path made relative to `ancestor`, which contains it.
    func relative(to ancestor: CodableDifference.Path) -> Self {
        let path = CodableDifference.Path(Array(path.components.dropFirst(ancestor.components.count)))
        return switch self {
        case .insert(_, let element): .insert(path: path, element: element)
        case .remove(_, let element): .remove(path: path, element: element)
        case .replace(_, let old, let new): .replace(path: path, old: old, new: new)
        }
    }
}

private extension CodableDifference.Path {
    /// Whether `other` lies strictly inside this path.
    func contains(_ other: Self) -> Bool {
        other.components.count > components.count && other.components.starts(with: components)
    }

    /// Whether this path comes first in the order `forEach` visits: keys sorted, indices ascending, and a
    /// path before the paths inside it.
    func precedes(_ other: Self) -> Bool {
        for (component, otherComponent) in zip(components, other.components) where component != otherComponent {
            switch (component, otherComponent) {
            case let (.key(key), .key(otherKey)): return key < otherKey
            case let (.index(index), .index(otherIndex)): return index < otherIndex
            case (.key, .index): return true
            case (.index, .key): return false
            }
        }
        return components.count < other.components.count
    }
}
