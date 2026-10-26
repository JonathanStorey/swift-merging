/// A value captured as plain data, the way JSON would hold it, so values of any `Codable` type can be
/// compared and merged piece by piece. `SnapshotEncoder` makes one, and `SnapshotDecoder` reads it back.
enum Snapshot: Equatable, Sendable {
    case null
    case bool(Bool)
    case int(Int64)
    case uint(UInt64)
    case double(Double)
    case string(String)
    case array([Snapshot])
    case object([String: Snapshot])
}

extension Snapshot {
    /// An integer, as `int` when it fits and `uint` otherwise.
    init(_ value: some BinaryInteger) {
        if let int = Int64(exactly: value) { self = .int(int) } else { self = .uint(UInt64(value)) }
    }
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
