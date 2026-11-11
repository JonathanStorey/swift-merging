#if canImport(SwiftData)
import Merging
import SwiftData

/// A SwiftData model whose properties merge one by one when another context, process, or device changes
/// the same object while this one has unsaved edits.
///
/// The merged properties live in a snapshot, a plain `Codable` struct. Written by hand, it's usually
/// `Mergeable`, where `@Merged` picks each property's strategy exactly as it does for any other value. A property only one side changed keeps
/// that side, and the strategy decides only when both changed it.
///
/// List every stored property in the snapshot, with or without `@Merged`. A SwiftData save writes the whole
/// object, so a property the snapshot leaves out loses the other side's change when the main context saves.
///
/// ```swift
/// @Model final class Note {
///     var title = ""
///     var likes = 0
/// }
///
/// extension Note: MergeableModel {
///     struct MergeSnapshot: Codable, Equatable, Mergeable {
///         @Merged(.keep(.theirs)) var title = ""
///         @Merged(.sum) var likes = 0
///     }
///
///     var mergeSnapshot: MergeSnapshot { MergeSnapshot(title: title, likes: likes) }
///
///     func applyMergeSnapshot(_ snapshot: MergeSnapshot) {
///         title = snapshot.title
///         likes = snapshot.likes
///     }
///
///     static var mergeKeyPaths: [PartialKeyPath<Note>] { [\.title, \.likes] }
/// }
/// ```
///
/// `@MergeableModel` writes this conformance from `@Merge(.strategy)` on the model's own properties, so it's
/// only written by hand to merge differently than the macro would.
public protocol MergeableModel: PersistentModel {
    associatedtype MergeSnapshot: Codable & Equatable & Sendable

    /// The merged properties' current values.
    var mergeSnapshot: MergeSnapshot { get }

    /// Sets the merged properties to a snapshot's values.
    func applyMergeSnapshot(_ snapshot: MergeSnapshot)

    /// The merged properties, so a change to anything else is left alone.
    static var mergeKeyPaths: [PartialKeyPath<Self>] { get }

    /// The snapshot's attributes that merge by a strategy, by name. A sync service that keeps one side's
    /// value of one of these, as CloudKit does while this device's edit waits to export, has the other
    /// side's value fetched so the two still merge. Empty by default.
    static var mergeStrategyProperties: [String] { get }

    /// Merges two edits of a snapshot property by property. A property with no strategy, or whose strategy
    /// can't combine the two, takes `side`, and every other property still merges.
    static func mergeSnapshots(base: MergeSnapshot, ours: MergeSnapshot, theirs: MergeSnapshot, favoring side: MergeSide) -> MergeSnapshot
}

extension MergeableModel {
    public static var mergeStrategyProperties: [String] { [] }
}

extension MergeableModel where MergeSnapshot: Mergeable {
    /// A `Mergeable` snapshot merges node by node, by its `@Merged` strategies.
    public static func mergeSnapshots(base: MergeSnapshot, ours: MergeSnapshot, theirs: MergeSnapshot, favoring side: MergeSide) -> MergeSnapshot {
        switch side {
        case .ours: CodableTotalMerge<MergeSnapshot, OursSide>().merge(base: base, ours: ours, theirs: theirs) ?? ours
        case .theirs: CodableTotalMerge<MergeSnapshot, TheirsSide>().merge(base: base, ours: ours, theirs: theirs) ?? theirs
        }
    }
}

/// What a property without a strategy merges to, or one whose strategy couldn't merge: `side`, as SwiftData
/// alone would keep it.
public enum MergeFallback {
    public static func value<Value>(base: Value, ours: Value, theirs: Value, favoring side: MergeSide) -> Value {
        side == .ours ? ours : theirs
    }
}

/// What a merge does when both sides changed a property and its strategy can't combine them, or the
/// property has no strategy. Only that property takes a side: every other property still merges.
public enum MergeConflictPolicy: Sendable {
    /// Keeps whichever side SwiftData would have kept with no merge at all, so a merge never does worse
    /// than SwiftData alone. A save from the main context writes the whole object, so its unsaved edits
    /// win over another context's save. An import from a sync service is written after this device's own
    /// save, so the import wins over that save.
    case storeDefault
    /// Keeps this device's edits.
    case keepOurs
    /// Takes what the other side saved.
    case keepTheirs

    /// The side a clash takes, where `store` is the side SwiftData alone would keep.
    func side(whereStoreKeeps store: MergeSide) -> MergeSide {
        switch self {
        case .storeDefault: store
        case .keepOurs: .ours
        case .keepTheirs: .theirs
        }
    }
}
#endif
