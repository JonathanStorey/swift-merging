/// A standard strategy, picked with dot syntax such as `@Merged(.max)`. Each shorthand is declared for the
/// value types it suits, so a mismatch such as `@Merged(.byWord) var count = 0` doesn't compile. `Kind`
/// names the strategy, and the strategy is rebuilt from it when a value decodes.
public struct StandardMerge<Value: Codable & Sendable, Kind: StandardMergeKind>: MergeStrategy {
    public init() {}

    public func merge(base: Value, ours: Value, theirs: Value) throws(MergeConflict<Value>) -> Value {
        do {
            return try kind.merge(base: base, ours: ours, theirs: theirs)
        } catch {
            throw MergeConflict(base: base, ours: ours, theirs: theirs)
        }
    }

    public func merge(ours: Value, theirs: Value) throws(MergeConflict<Value>) -> Value {
        do {
            return try kind.merge(base: nil, ours: ours, theirs: theirs)
        } catch {
            throw MergeConflict(ours: ours, theirs: theirs)
        }
    }

    private var kind: any StandardMerging.Type { Kind.self as! any StandardMerging.Type }
}

/// The name of a standard strategy, one of the types in `MergeKind`.
public protocol StandardMergeKind: Sendable {}

/// The standard strategies' names, as they appear in `StandardMerge`'s type.
public enum MergeKind {}

/// How a standard strategy merges. Each shorthand's constraints guarantee the value's type, so a merge can
/// cast to it. A merge that needs a base throws when there's none.
protocol StandardMerging: StandardMergeKind {
    static func merge<Value: Codable & Sendable>(base: Value?, ours: Value, theirs: Value) throws -> Value
}

/// Thrown by a standard strategy that can't merge the versions.
struct Unmergeable: Error {}

extension Merged {
    /// Merges with a standard strategy, such as `@Merged(.max)`.
    public init<Value, Kind>(wrappedValue: Value, _ strategy: StandardMerge<Value, Kind>) where Strategy == StandardMerge<Value, Kind> {
        self.init(wrappedValue: wrappedValue, strategy as Strategy)
    }
}
