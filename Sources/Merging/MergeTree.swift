/// A value's `Snapshot`, with the rules its parts merge by: `@Merged` strategies, nested `Mergeable`
/// types, sets, and dictionaries. `SnapshotEncoder` makes one, and `SnapshotDecoder` reads it back.
enum MergeTree: Equatable, Sendable {
    case null
    case bool(Bool)
    case int(Int64)
    case uint(UInt64)
    case double(Double)
    case string(String)
    case array([MergeTree])
    case object([String: MergeTree])
    /// A part that merges by a rule of its own rather than by its shape.
    indirect case merged(MergeTree, MergeRule)
}

extension MergeTree {
    /// An integer, as `int` when it fits and `uint` otherwise.
    init(_ value: some BinaryInteger) {
        if let int = Int64(exactly: value) { self = .int(int) } else { self = .uint(UInt64(value)) }
    }
}

/// How part of a tree merges when it isn't by its shape: a `@Merged` strategy, or a nested `Mergeable`
/// type's own merge. It decodes the versions, merges them, and encodes the result. Rules don't take part in
/// equality, so two snapshots are equal when their data is.
struct MergeRule: Sendable, Equatable {
    /// Merges ours, theirs, and the base when there is one.
    let merge: @Sendable (MergeTree, MergeTree, MergeTree?) throws(MergeConflict<MergeTree>) -> MergeTree

    init<Value: Codable>(_ type: Value.Type, merge: @escaping @Sendable (Value, Value, Value?) throws -> Value) {
        self.merge = { ours, theirs, base throws(MergeConflict<MergeTree>) in
            do {
                let decoder = SnapshotDecoder()
                let original = try base.map { try decoder.decode(Value.self, from: $0) }
                let merged = try merge(decoder.decode(Value.self, from: ours), decoder.decode(Value.self, from: theirs), original)
                return try SnapshotEncoder().encode(merged)
            } catch {
                throw MergeConflict(base: base, ours: ours, theirs: theirs)
            }
        }
    }

    init(merge: @escaping @Sendable (MergeTree, MergeTree, MergeTree?) throws(MergeConflict<MergeTree>) -> MergeTree) {
        self.merge = merge
    }

    static func == (lhs: Self, rhs: Self) -> Bool { true }
}

/// A value that brings its own `MergeRule` to the snapshot it encodes into.
protocol MergeRuled {
    var mergeRule: MergeRule { get }
}

/// A key for an array element, or for a superclass's or other key-less part of a value.
struct SnapshotKey: CodingKey {
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

    static let `super` = SnapshotKey(stringValue: "super")
}
