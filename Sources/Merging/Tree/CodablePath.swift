/// Where a value sits inside another: the keys and indices that lead to it, written and printed as
/// `"child.grandchildren[2]"`. A collection of its components, like `IndexPath`.
///
/// ```swift
/// change.path == "address.city"                     // a string literal, parsed where it's written
/// let exact: CodablePath = ["config", "v1.2"]       // an array literal, for a key with a dot
/// if case .index(let index)? = change.path.last { print(index) }
/// schema["child.grandchildren[0]"]                  // .string
/// ```
public struct CodablePath: Hashable, Sendable {
    public enum Component: Hashable, Sendable {
        /// An object's property or entry.
        case key(String)
        /// An array's element.
        case index(Int)
        /// A set's member, which has no index or key, so it's named by its value.
        case member(CodableRepresentation)
    }

    var components: [Component]

    /// The path to the value itself.
    public init() {
        components = []
    }

    func appending(_ component: Component) -> CodablePath {
        var path = self
        path.append(component)
        return path
    }
}

extension CodablePath: RandomAccessCollection, MutableCollection, RangeReplaceableCollection {
    public var startIndex: Int { components.startIndex }
    public var endIndex: Int { components.endIndex }

    public subscript(position: Int) -> Component {
        get { components[position] }
        set { components[position] = newValue }
    }

    public mutating func replaceSubrange(_ subrange: Range<Int>, with newElements: some Collection<Component>) {
        components.replaceSubrange(subrange, with: newElements)
    }
}

extension CodableRepresentation {
    /// The node at `path`, if the tree has one there. Setting it replaces that node, and setting `nil`
    /// removes it. Setting a path whose parent doesn't exist does nothing.
    subscript(path: CodablePath) -> CodableRepresentation? {
        get { self[path.components[...]] }
        set { self[path.components[...]] = newValue }
    }

    private subscript(components: ArraySlice<CodablePath.Component>) -> CodableRepresentation? {
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

    private subscript(component: CodablePath.Component) -> CodableRepresentation? {
        get {
            switch component {
            case .key(let key): self[key]
            case .index(let index): self[index]
            case .member(let member): members?.matching(member)
            }
        }
        set {
            switch component {
            case .key(let key): self[key] = newValue
            case .index(let index): self[index] = newValue
            case .member(let member):
                guard case .set(var members) = self else { return }
                if let existing = members.matching(member) { members.remove(existing) }
                if let newValue { members.insert(newValue) }
                self = .set(members)
            }
        }
    }

    /// Visits every node, depth first: this one, then each child in turn, with object keys in order.
    ///
    /// ```swift
    /// tree.forEach { path, node in print(path, node) }
    /// ```
    func forEach(_ body: (CodablePath, CodableRepresentation) throws -> Void) rethrows {
        try walk(from: CodablePath(), body)
    }

    private func walk(from path: CodablePath, _ body: (CodablePath, CodableRepresentation) throws -> Void) rethrows {
        try body(path, self)
        switch self {
        case .array(let array):
            for (index, element) in array.enumerated() { try element.walk(from: path.appending(.index(index)), body) }
        case .object(let object):
            for key in object.keys.sorted() { try object[key]!.walk(from: path.appending(.key(key)), body) }
        case .set(let members):
            for member in members.ordered { try member.walk(from: path.appending(.member(member)), body) }
        default:
            break
        }
    }
}

extension CodablePath: ExpressibleByArrayLiteral {
    public init(arrayLiteral components: Component...) {
        self.init(components)
    }
}

extension CodablePath: ExpressibleByStringLiteral {
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

extension CodablePath.Component: ExpressibleByStringLiteral, ExpressibleByIntegerLiteral {
    public init(stringLiteral key: String) { self = .key(key) }
    public init(integerLiteral index: Int) { self = .index(index) }
}

extension CodablePath: CustomStringConvertible {
    /// Keys joined with dots, indices in brackets and members in braces, as in `items[0].title` or
    /// `tags{"swift"}`. The value itself is `.`.
    public var description: String {
        guard !isEmpty else { return "." }
        var text = ""
        for component in self {
            switch component {
            case .key(let key): text += text.isEmpty ? key : "." + key
            case .index(let index): text += "[\(index)]"
            case .member(let member): text += "{\(member)}"
            }
        }
        return text
    }
}

extension CodablePath: Codable {
    /// The components as an array: `["child", "grandchildren", 0]`, with a member as `{"member": "swift"}`.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(components)
    }

    public init(from decoder: any Decoder) throws {
        self.init(try decoder.singleValueContainer().decode([Component].self))
    }
}

extension CodablePath.Component: Codable {
    /// A key as a string, an index as a number, and a member as `{"member": value}`.
    public func encode(to encoder: any Encoder) throws {
        switch self {
        case .key(let key):
            var container = encoder.singleValueContainer()
            try container.encode(key)
        case .index(let index):
            var container = encoder.singleValueContainer()
            try container.encode(index)
        case .member(let member):
            var container = encoder.container(keyedBy: MemberKey.self)
            try container.encode(member, forKey: .member)
        }
    }

    public init(from decoder: any Decoder) throws {
        if let container = try? decoder.singleValueContainer() {
            if let index = try? container.decode(Int.self) {
                self = .index(index)
                return
            }
            if let key = try? container.decode(String.self) {
                self = .key(key)
                return
            }
        }
        self = .member(try decoder.container(keyedBy: MemberKey.self).decode(CodableRepresentation.self, forKey: .member))
    }

    private enum MemberKey: String, CodingKey {
        case member
    }
}

extension Set<CodableRepresentation> {
    /// The members in a fixed order, by their text, since a set has none of its own.
    var ordered: [CodableRepresentation] {
        sorted { $0.description < $1.description }
    }

    /// The member equal to `member`, or failing that, one with the same JSON form, so a `.string` read
    /// from JSON finds the `.uuid` it was written from.
    func matching(_ member: CodableRepresentation) -> CodableRepresentation? {
        if contains(member) { return member }
        guard let plain = try? member.data else { return nil }
        return first { (try? $0.data) == plain }
    }
}
