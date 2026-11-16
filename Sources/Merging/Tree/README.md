# Codable types

The public surface of `CodableRepresentation`, `CodableDifference`, `CodablePath` and `CodableSchema`, with
the types nested in them. They are the only public `Codable…` types apart from the strategies `CodableTotalMerge` and
`CodableNodeMerge`, which [Strategies](../Strategies/README.md) covers. Everything else in this folder
(`MergeTree`, `TreeEncoder`, `TreeDecoder`, `SchemaProbe`) is internal.

| Type | Kind | Conforms to |
| --- | --- | --- |
| `CodableRepresentation` | enum | `Hashable`, `Sendable`, `Codable`, `CustomStringConvertible`, the seven `ExpressibleBy…Literal` protocols |
| `CodableDifference` | struct | `RandomAccessCollection`, `Hashable`, `Sendable`, `Codable` |
| `CodableDifference.Change` | enum | `Hashable`, `Sendable`, `Codable`, `CustomStringConvertible` |
| `CodablePath` | struct | `RandomAccessCollection`, `MutableCollection`, `RangeReplaceableCollection`, `Hashable`, `Sendable`, `Codable`, `CustomStringConvertible`, `ExpressibleByStringLiteral`, `ExpressibleByArrayLiteral` |
| `CodablePath.Component` | enum | `Hashable`, `Sendable`, `Codable`, `ExpressibleByStringLiteral`, `ExpressibleByIntegerLiteral` |
| `CodableSchema` | indirect enum | `Hashable`, `Sendable`, `Codable`, `CustomStringConvertible`, `Identifiable` |

## CodableRepresentation

A value's stored form, with typed leaves that round-trip exactly.

```swift
public enum CodableRepresentation {
    case null
    case bool(Bool)
    case integer(Int128)         // any integer type up to 64 bits, signed or not
    case double(Double)          // Double, or a Float through its shortest form, NaN and infinities too
    case string(String)
    case date(Date)
    case data(Data)
    case uuid(UUID)
    case decimal(Decimal)
    case url(URL)
    case array([CodableRepresentation])
    case set(Set<CodableRepresentation>)   // JSON holds it as an array, sorted
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
| Equality | `==` and `hash(into:)`, comparing a double bit for bit, so a NaN equals itself and `-0.0` isn't `0.0` |
| Literals | `nil`, `true`, `42` (as `Int128`), `1.5`, `"text"`, `[…]`, `["key": …]` |

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
| Codable | `{"schemaID": "…", "changes": [...]}` |

### Change

| Member | Signature |
| --- | --- |
| Cases | `insert(path: CodablePath, element: ChangeElement)`, `remove(path: CodablePath, element: ChangeElement)`, `replace(path: CodablePath, old: ChangeElement, new: ChangeElement)` |
| Where | `var path: CodablePath` |
| Text | `var description: String`, as `+ path: new`, `- path: old` or `~ path: old → new` |

## CodablePath

Where a value sits inside another, as keys and indices. A collection of `Component`, like `IndexPath` is of
`Int`, so `count`, `last`, `starts(with:)`, `append(_:)`, `dropLast()` and the rest come from the standard
library.

| Member | Signature |
| --- | --- |
| The value itself | `init()` |
| From components | `init(_ elements: some Sequence<Component>)`, from `RangeReplaceableCollection` |
| Collection | `var startIndex: Int`, `var endIndex: Int`, `subscript(position: Int) -> Component { get set }`, `mutating func replaceSubrange(_:with:)` |
| Component cases | `key(String)`, `index(Int)`, `member(CodableRepresentation)` for a set's member |
| Literals | `"child.grandchildren[2]"` parsed, `["config", "v1.2"]` exact, a component from `"key"` or `2` |
| Text | `var description: String`, as `child.grandchildren[2]` or `tags{"swift"}`, or `.` for the value itself |
| Codable | an array of strings, integers and `{"member": value}` objects |

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
| Read a type | `init<T: Decodable>(_ type: T.Type) throws` |
| Look up | `subscript(path: CodablePath) -> CodableSchema?` |
| Stable id | `var id: UUID`, a version 8 UUID hashed from the schema |
| Text | `var description: String`, as `{age: integer, id: uuid, name: string?}` |
| Codable | `"string"`, `{"optional": "string"}`, `{"object": {…}}` |

## Limits

Encoding, decoding, diffing and comparing all recurse once per level of nesting, so a value nested a
thousand levels deep can overflow a secondary thread's stack. `JSONDecoder` stops at 512 levels for the same
reason. Real models stay far below either limit.

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

## Possible further changes

- **`Mergeable.MergeBase`** existed so `CodableDifference` could merge from a `CodableRepresentation`. With
  that conformance gone, every `Mergeable` type's base is itself, so the associated type could go, and
  `MergeableMerge`'s `where Value.MergeBase == Value` with it.
- **A public `CodableDifference.init?(_:schemaID:)`**, like `CollectionDifference.init?(_:)`, was
  considered and left out.
