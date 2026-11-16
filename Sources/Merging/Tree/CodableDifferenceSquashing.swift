import Foundation

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
    func relative(to ancestor: CodablePath) -> Self {
        let path = CodablePath(path.dropFirst(ancestor.count))
        return switch self {
        case .insert(_, let element): .insert(path: path, element: element)
        case .remove(_, let element): .remove(path: path, element: element)
        case .replace(_, let old, let new): .replace(path: path, old: old, new: new)
        }
    }
}

private extension CodablePath {
    /// Whether `other` lies strictly inside this path.
    func contains(_ other: Self) -> Bool {
        other.count > count && other.starts(with: self)
    }

    /// Whether this path comes first in the order `forEach` visits: keys sorted, indices ascending, and a
    /// path before the paths inside it.
    func precedes(_ other: Self) -> Bool {
        for (component, otherComponent) in zip(self, other) where component != otherComponent {
            switch (component, otherComponent) {
            case let (.key(key), .key(otherKey)): return key < otherKey
            case let (.index(index), .index(otherIndex)): return index < otherIndex
            case (.key, .index): return true
            case (.index, .key): return false
            }
        }
        return count < other.count
    }
}
