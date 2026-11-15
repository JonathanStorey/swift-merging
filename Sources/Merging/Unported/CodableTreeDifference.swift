extension CodableTree {
    /// One difference between two trees, at the deepest path where they differ.
    public enum Change: Hashable, Sendable {
        case added(Path, CodableTree)
        case removed(Path, CodableTree)
        case changed(Path, from: CodableTree, to: CodableTree)

        public var path: Path {
            switch self {
            case .added(let path, _), .removed(let path, _), .changed(let path, _, _): path
            }
        }
    }

    /// What changed from `other` to this tree, in the order `forEach` visits. Objects compare key by key and
    /// arrays index by index, so an element inserted mid-array shows as changes to the ones after it.
    ///
    /// ```swift
    /// let changes = try CodableTree(encoding: edited).difference(from: CodableTree(encoding: original))
    /// changes.map(\.description)             // ["~ age: 30 → 31", "+ tags[2]: \"c\""]
    /// ```
    public func difference(from other: CodableTree) -> [Change] {
        var changes: [Change] = []
        Self.collect(from: other, to: self, at: .root, into: &changes)
        return changes
    }

    private static func collect(from old: CodableTree, to new: CodableTree, at path: Path, into changes: inout [Change]) {
        guard old != new else { return }
        switch (old, new) {
        case (.object(let before), .object(let after)):
            for key in Set(before.keys).union(after.keys).sorted() {
                compare(before[key], after[key], at: path.appending(.key(key)), into: &changes)
            }
        case (.array(let before), .array(let after)):
            for index in 0..<max(before.count, after.count) {
                // Not `? element : nil`, which would build `.null` from the literal.
                let old = before.indices.contains(index) ? Optional(before[index]) : .none
                let new = after.indices.contains(index) ? Optional(after[index]) : .none
                compare(old, new, at: path.appending(.index(index)), into: &changes)
            }
        default:
            changes.append(.changed(path, from: old, to: new))
        }
    }

    private static func compare(_ old: CodableTree?, _ new: CodableTree?, at path: Path, into changes: inout [Change]) {
        switch (old, new) {
        case let (old?, new?): collect(from: old, to: new, at: path, into: &changes)
        case let (old?, nil): changes.append(.removed(path, old))
        case let (nil, new?): changes.append(.added(path, new))
        case (nil, nil): break
        }
    }
}

extension CodableTree.Change: CustomStringConvertible {
    /// `+` for added, `-` for removed and `~` for changed, then the path and the values.
    public var description: String {
        switch self {
        case .added(let path, let value): "+ \(path): \(value)"
        case .removed(let path, let value): "- \(path): \(value)"
        case .changed(let path, let old, let new): "~ \(path): \(old) → \(new)"
        }
    }
}
