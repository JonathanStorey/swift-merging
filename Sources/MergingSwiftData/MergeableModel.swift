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

    /// Merges two edits of a snapshot property by property. A property both sides changed and its strategy
    /// can't combine takes `side`, and every other property still merges.
    static func mergeSnapshots(base: MergeSnapshot, ours: MergeSnapshot, theirs: MergeSnapshot, favoring side: MergeSide) -> MergeSnapshot
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

/// What a merge does when both sides changed a property and its strategy can't combine them. Only that
/// property takes the side: every other property still merges.
public enum MergeConflictPolicy: Sendable {
    /// Keeps this device's unsaved edits.
    case keepOurs
    /// Takes what the other side saved.
    case keepTheirs
}
#endif
