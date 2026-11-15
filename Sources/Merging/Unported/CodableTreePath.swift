extension CodableTree {
    /// Where a node sits in a tree: the keys and indices that lead to it from the root.
    ///
    /// ```swift
    /// let path: CodableTree.Path = ["address", "city"]
    /// tree[path]?.string                                  // "Oslo"
    /// print(["tags", 2] as CodableTree.Path)             // tags[2]
    /// ```
    public struct Path: Hashable, Sendable {
        public enum Component: Hashable, Sendable {
            /// An object's property or entry.
            case key(String)
            /// An array's element.
            case index(Int)
        }

        public var components: [Component]

        public init(_ components: [Component] = []) {
            self.components = components
        }

        /// The path to the tree itself.
        public static let root = Path()

        public func appending(_ component: Component) -> Path {
            Path(components + [component])
        }
    }

    /// The node at `path`, if the tree has one there. Setting it replaces that node, and setting `nil`
    /// removes it. Setting a path whose parent doesn't exist does nothing.
    public subscript(path: Path) -> CodableTree? {
        get { self[path.components[...]] }
        set { self[path.components[...]] = newValue }
    }

    private subscript(components: ArraySlice<Path.Component>) -> CodableTree? {
        get {
            guard let first = components.first else { return self }
            return self[first]?[components.dropFirst()]
        }
        set {
            guard let first = components.first else {
                self = newValue ?? .null
                return
            }
            let rest = components.dropFirst()
            guard !rest.isEmpty else {
                self[first] = newValue
                return
            }
            guard var child = self[first] else { return }
            child[rest] = newValue
            self[first] = child
        }
    }

    private subscript(component: Path.Component) -> CodableTree? {
        get {
            switch component {
            case .key(let key): self[key]
            case .index(let index): self[index]
            }
        }
        set {
            switch component {
            case .key(let key): self[key] = newValue
            case .index(let index): self[index] = newValue
            }
        }
    }

    /// Visits every node, depth first: this one, then each child in turn, with object keys in order.
    ///
    /// ```swift
    /// tree.forEach { path, node in print(path, node) }
    /// ```
    public func forEach(_ body: (Path, CodableTree) throws -> Void) rethrows {
        try walk(from: .root, body)
    }

    private func walk(from path: Path, _ body: (Path, CodableTree) throws -> Void) rethrows {
        try body(path, self)
        switch self {
        case .array(let array):
            for (index, element) in array.enumerated() { try element.walk(from: path.appending(.index(index)), body) }
        case .object(let object):
            for key in object.keys.sorted() { try object[key]!.walk(from: path.appending(.key(key)), body) }
        default:
            break
        }
    }
}

extension CodableTree.Path: ExpressibleByArrayLiteral {
    public init(arrayLiteral components: Component...) {
        self.init(components)
    }
}

extension CodableTree.Path.Component: ExpressibleByStringLiteral, ExpressibleByIntegerLiteral {
    public init(stringLiteral key: String) { self = .key(key) }
    public init(integerLiteral index: Int) { self = .index(index) }
}

extension CodableTree.Path: CustomStringConvertible {
    /// Keys joined with dots and indices in brackets, as in `items[0].title`. The root is `.`.
    public var description: String {
        guard !components.isEmpty else { return "." }
        var text = ""
        for component in components {
            switch component {
            case .key(let key): text += text.isEmpty ? key : "." + key
            case .index(let index): text += "[\(index)]"
            }
        }
        return text
    }
}
