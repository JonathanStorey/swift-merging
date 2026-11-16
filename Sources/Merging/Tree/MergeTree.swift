import Foundation

/// A value's `CodableRepresentation`, marking the parts that merge by a kind of their own rather than by their shape:
/// sets and dictionaries. `TreeEncoder` makes one, and `TreeDecoder` reads it back.
enum MergeTree: Equatable, Sendable {
    case null
    case bool(Bool)
    case integer(Int128)
    case double(Double)
    case string(String)
    case date(Date)
    case data(Data)
    case uuid(UUID)
    case decimal(Decimal)
    case url(URL)
    case array([MergeTree])
    case object([String: MergeTree])
    /// A part that merges by a kind of its own rather than by its shape.
    indirect case merged(MergeTree, MergeKind)
}

extension MergeTree {
    /// An integer, from any integer type up to 64 bits.
    init(_ value: some BinaryInteger) {
        self = .integer(Int128(clamping: value))
    }

    /// The typed leaf for a `Date`, `Data`, `UUID`, `Decimal` or `URL`, or for a `CodableRepresentation`,
    /// which is a tree already. `nil` for anything else.
    init?(leaf value: Any) {
        switch value {
        case let value as Date: self = .date(value)
        case let value as Data: self = .data(value)
        case let value as UUID: self = .uuid(value)
        case let value as Decimal: self = .decimal(value)
        case let value as URL: self = .url(value)
        case let value as CodableRepresentation: self = MergeTree(value)
        default: return nil
        }
    }
}

extension MergeTree {
    /// Text that's the same for equal trees and different for different ones, with object keys sorted.
    var canonical: String {
        switch self {
        case .null: "null"
        case .bool(let value): "\(value)"
        case .integer(let value): "i\(value)"
        case .double(let value): "d\(value)"
        case .string(let value): value.debugDescription
        case .date(let value): "t\(value.timeIntervalSinceReferenceDate)"
        case .data(let value): "b" + value.base64EncodedString()
        case .uuid(let value): "g" + value.uuidString
        case .decimal(let value): "m\(value)"
        case .url(let value): "l" + value.absoluteString.debugDescription
        case .array(let values): "[" + values.map(\.canonical).joined(separator: ",") + "]"
        case .object(let object):
            "{" + object.keys.sorted().map { $0.debugDescription + ":" + object[$0]!.canonical }.joined(separator: ",") + "}"
        case .merged(let data, _): data.canonical
        }
    }
}

/// Two versions of part of a tree that can't be merged, which ends the merge.
struct MergeClash: Error {}

/// How a part of a tree merges when it isn't by its shape.
enum MergeKind: Sendable {
    /// A set, which encodes in no particular order, so it merges by membership.
    case set
    /// A dictionary. One with string or integer keys encodes as an object, which merges by key anyway. Any
    /// other encodes as a flat array of keys and values, which would mangle in an array merge.
    case dictionary
}

/// A type whose encoded form merges by a kind of its own, such as `Set`.
protocol MergeKinded {
    static var mergeKind: MergeKind { get }
}

extension Set: MergeKinded {
    static var mergeKind: MergeKind { .set }
}

extension Dictionary: MergeKinded {
    static var mergeKind: MergeKind { .dictionary }
}

/// A key for an array element, or for a superclass's or other key-less part of a value.
struct TreeKey: CodingKey {
    let stringValue: String
    let intValue: Int?

    init(stringValue: String) {
        self.stringValue = stringValue
        intValue = nil
    }

    init(intValue: Int) {
        stringValue = "Index \(intValue)"
        self.intValue = intValue
    }

    static let `super` = TreeKey(stringValue: "super")
}
