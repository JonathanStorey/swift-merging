# Codable types

The public surface of `CodableRepresentation`, `CodableDifference` and `CodableSchema`, with the types
nested in them. They are the only public `Codable…` types apart from the strategies `CodableTotalMerge` and
`CodableNodeMerge`, which [Strategies](../Strategies/README.md) covers. Everything else in this folder
(`MergeTree`, `TreeEncoder`, `TreeDecoder`, `SchemaProbe`) is internal.

| Type | Kind | Conforms to |
| --- | --- | --- |
| `CodableRepresentation` | enum | `Hashable`, `Sendable`, `Codable`, `CustomStringConvertible`, the seven `ExpressibleBy…Literal` protocols |
| `CodableDifference` | struct | `RandomAccessCollection`, `Hashable`, `Sendable`, `Codable`, `Mergeable` |
| `CodableDifference.Change` | enum | `Hashable`, `Sendable`, `Codable`, `CustomStringConvertible` |
| `CodableDifference.Path` | struct | `Hashable`, `Sendable`, `Codable`, `CustomStringConvertible`, `ExpressibleByStringLiteral`, `ExpressibleByArrayLiteral` |
| `CodableDifference.Path.Component` | enum | `Hashable`, `Sendable`, `Codable`, `ExpressibleByStringLiteral`, `ExpressibleByIntegerLiteral` |
| `CodableSchema` | indirect enum | `Hashable`, `Sendable`, `Codable`, `CustomStringConvertible`, `Identifiable` |

## CodableRepresentation

A value's stored form, with typed leaves that round-trip exactly.

```swift
public enum CodableRepresentation {
    case null
    case bool(Bool)
    case int(Int64)
    case uint(UInt64)            // only above Int64.max
    case double(Double)          // Double, or a Float through its shortest form
    case string(String)
    case date(Date)
    case data(Data)
    case uuid(UUID)
    case decimal(Decimal)
    case url(URL)
    case array([CodableRepresentation])
    case object([String: CodableRepresentation])
}
```

| Member | Signature |
| --- | --- |
| Encode a value | `init(encoding value: some Encodable) throws` |
| Decode a value | `func decode<T: Decodable>(as type: T.Type = T.self) throws -> T` |
| Top-level fields | `func dictionary() -> [String: CodableRepresentation]?` |
| JSON bytes | `var data: Data { get throws }` |
| JSON text | `var json: String { get throws }` |
| From JSON bytes | `init(data: Data) throws` |
| From JSON text | `init(json: String) throws` |
| JSON-like text | `var description: String` |
| Codable | `func encode(to encoder: any Encoder) throws`, `init(from decoder: any Decoder) throws` |
| Literals | `nil`, `true`, `42` (as `Int64`), `1.5`, `"text"`, `[…]`, `["key": …]` |

## CodableDifference

What changed between two versions of a `Codable` value, shaped like `CollectionDifference`.

| Member | Signature |
| --- | --- |
| Element type | `typealias ChangeElement = CodableRepresentation` |
| Make one | `init<Value: Codable>(from old: Value, to new: Value) throws` |
| Schema it was made for | `let schemaID: UUID?` |
| Collection | `var startIndex: Int`, `var endIndex: Int`, `subscript(position: Int) -> Change` |
| By kind | `var insertions: [Change]`, `var removals: [Change]`, `var replacements: [Change]` |
| Undo | `func inverse() -> CodableDifference` |
| Squash | `func followed(by next: CodableDifference) -> CodableDifference?` |
| Merge (`Mergeable`) | `typealias MergeBase = CodableRepresentation` |
| | `func merging(with theirs: CodableDifference, favoring side: MergeSide) throws -> CodableDifference` |
| | `func merging(with theirs: CodableDifference, from base: CodableRepresentation, favoring side: MergeSide) throws -> CodableDifference` |
| Merge with a typed base | `func merging<Value: Codable & Sendable>(with theirs: CodableDifference, from base: Value, favoring side: MergeSide) throws -> CodableDifference` |
| | `mutating func merge<Value: Codable & Sendable>(with theirs: CodableDifference, from base: Value, favoring side: MergeSide) throws` |
| Codable | `{"schemaID": "…", "changes": [...]}` |

Through `Mergeable` it also gets `mutating func merge(with:favoring:)`, `mutating func merge(with:from:favoring:)`,
`static func merge(ours:theirs:favoring:)` and `static func merge(base:ours:theirs:favoring:)`.

### Change

| Member | Signature |
| --- | --- |
| Cases | `insert(path: Path, element: ChangeElement)`, `remove(path: Path, element: ChangeElement)`, `replace(path: Path, old: ChangeElement, new: ChangeElement)` |
| Where | `var path: Path` |
| Text | `var description: String`, as `+ path: new`, `- path: old` or `~ path: old → new` |

### Path and Component

| Member | Signature |
| --- | --- |
| Components | `var components: [Component]`, `init(_ components: [Component])` |
| Component cases | `key(String)`, `index(Int)` |
| Literals | `"child.grandchildren[2]"` parsed, `["config", "v1.2"]` exact, a component from `"key"` or `2` |
| Text | `var description: String`, as `child.grandchildren[2]` |
| Codable | an array of strings and integers |

## CodableSchema

The shape of a `Decodable` type, read from the type alone.

```swift
public indirect enum CodableSchema {
    case bool, integer, double, string, date, data, uuid, decimal, url
    case enumeration([CodableRepresentation])
    case optional(CodableSchema)
    case array(CodableSchema)
    case set(CodableSchema)
    case dictionary(CodableSchema)
    case object([String: CodableSchema])
}
```

| Member | Signature |
| --- | --- |
| Path type | `typealias Path = CodableDifference.Path` |
| Read a type | `init<T: Decodable>(_ type: T.Type) throws` |
| Look up | `subscript(path: Path) -> CodableSchema?` |
| Stable id | `var id: UUID`, a version 8 UUID hashed from the schema |
| Text | `var description: String`, as `{age: integer, id: uuid, name: string?}` |
| Codable | `"string"`, `{"optional": "string"}`, `{"object": {…}}` |

## Extensions on types we don't own

There is one public extension:

```swift
extension Encodable where Self: Decodable {
    public func applying(_ difference: CodableDifference) throws -> Self
}
```

Every `Codable` type gets `applying(_:)`. It mirrors `BidirectionalCollection.applying(_:)` for a
`CollectionDifference`, except that it throws where the standard library returns `nil`.

Internally, `Set` and `Dictionary` conform to `MergeKinded` so the encoder can mark them. That conformance
isn't visible outside the module.

## Where the surface could trim or align

In order of value:

1. **Make `Path` a collection, like `IndexPath`.** `Path` is an array of components wrapped in a struct, so
   it should be a `RandomAccessCollection` and `RangeReplaceableCollection` of `Component`, as `IndexPath`
   is of `Int`. Then `count`, `last`, `starts(with:)`, `dropLast()`, `append(_:)` and `+` come for free, and
   `components` can go. `if case .index(let i)? = path.last` reads better than
   `path.components.last`.
2. **Make `CodableDifference.init(_:schemaID:)` public, as `CollectionDifference.init?(_:)` is.** Right now
   `difference.filter { … }` gives `[Change]` with no way back to a difference. A public
   `init?(_ changes: some Sequence<Change>, schemaID: UUID? = nil)` lets a caller drop or keep changes by
   path and still apply the result. Like the standard library's init, it would return `nil` for changes
   that can't belong together, such as two at the same path.
3. **The two `merging(with:from:favoring:)` overloads on `CodableDifference` share labels but merge
   differently.** With a `CodableRepresentation` base, a set merges by position. With a typed base, it
   merges by membership. The caller can't tell from the call site. Relabeling the typed one as
   `merging(with:applyingTo:favoring:)` would make the difference visible. The other option is dropping the
   mutating typed overload, since `Mergeable` already supplies a mutating one.
4. **Hoist `Path` to the top level as `CodablePath`.** It's used by `CodableDifference`, `CodableSchema`
   and, internally, `CodableRepresentation`, so it doesn't belong to `CodableDifference` alone. This adds a
   top-level name but removes the `CodableSchema.Path` typealias. It is optional, and it pairs well with
   item 1.
5. **Consider dropping `ChangeElement`.** It exists to echo `CollectionDifference<ChangeElement>`, but
   there it's a generic parameter, and here it's always `CodableRepresentation`. Keeping it costs little,
   so this is the weakest item.

What I would keep as it is:
- `dictionary()`, even though it overlaps `if case .object(let fields)`, because it names the CloudKit use.
- `init(encoding:)` and `decode(as:)`, which mirror `JSONDecoder.decode(_:from:)`.
- The literal conformances.
- `CodableSchema`'s cached `init(_:)` and its `Identifiable` id.
