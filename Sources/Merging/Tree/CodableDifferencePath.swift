extension CodableDifference {
    /// Where a change sits in a value: the keys and indices that lead to it, written and printed as
    /// `"child.grandchildren[2]"`.
    ///
    /// ```swift
    /// change.path == "address.city"                          // a string literal, parsed where it's written
    /// let exact: CodableDifference.Path = ["config", "v1.2"] // an array literal, for a key with a dot
    /// if case .index(let index)? = change.path.components.last { print(index) }
    /// ```
    public struct Path: Hashable, Sendable {
        public enum Component: Hashable, Sendable {
            /// An object's property or entry.
            case key(String)
            /// An array's element.
            case index(Int)
        }

        public var components: [Component]

        public init(_ components: [Component]) {
            self.components = components
        }

        /// The path to the value itself.
        static let root = Path([])

        func appending(_ component: Component) -> Path {
            Path(components + [component])
        }
    }
}

extension CodableRepresentation {
    /// The node at `path`, if the tree has one there. Setting it replaces that node, and setting `nil`
    /// removes it. Setting a path whose parent doesn't exist does nothing.
    subscript(path: CodableDifference.Path) -> CodableRepresentation? {
        get { self[path.components[...]] }
        set { self[path.components[...]] = newValue }
    }

    private subscript(components: ArraySlice<CodableDifference.Path.Component>) -> CodableRepresentation? {
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

    private subscript(component: CodableDifference.Path.Component) -> CodableRepresentation? {
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
    func forEach(_ body: (CodableDifference.Path, CodableRepresentation) throws -> Void) rethrows {
        try walk(from: .root, body)
    }

    private func walk(from path: CodableDifference.Path, _ body: (CodableDifference.Path, CodableRepresentation) throws -> Void) rethrows {
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

extension CodableDifference.Path: ExpressibleByArrayLiteral {
    public init(arrayLiteral components: Component...) {
        self.init(components)
    }
}

extension CodableDifference.Path: ExpressibleByStringLiteral {
    /// Keys separated by dots, with indices in brackets: `"items[0].title"`, or `"."` for the value itself.
    /// A key that holds a dot or a bracket needs the array literal instead.
    public init(stringLiteral path: String) {
        var components: [Component] = []
        for segment in path.split(separator: ".") {
            let pieces = segment.split(separator: "[", omittingEmptySubsequences: false)
            if let key = pieces.first, !key.isEmpty { components.append(.key(String(key))) }
            for piece in pieces.dropFirst() {
                if piece.last == "]", let index = Int(piece.dropLast()) {
                    components.append(.index(index))
                } else {
                    components.append(.key("[" + String(piece)))
                }
            }
        }
        self.init(components)
    }
}

extension CodableDifference.Path.Component: ExpressibleByStringLiteral, ExpressibleByIntegerLiteral {
    public init(stringLiteral key: String) { self = .key(key) }
    public init(integerLiteral index: Int) { self = .index(index) }
}

extension CodableDifference.Path: CustomStringConvertible {
    /// Keys joined with dots and indices in brackets, as in `items[0].title`. The value itself is `.`.
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

extension CodableDifference.Path: Codable {
    /// The keys and indices as an array: `["child", "grandchildren", 0]`.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(components)
    }

    public init(from decoder: any Decoder) throws {
        self.init(try decoder.singleValueContainer().decode([Component].self))
    }
}

extension CodableDifference.Path.Component: Codable {
    /// A key as a string and an index as a number.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .key(let key): try container.encode(key)
        case .index(let index): try container.encode(index)
        }
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let index = try? container.decode(Int.self) {
            self = .index(index)
        } else {
            self = .key(try container.decode(String.self))
        }
    }
}
