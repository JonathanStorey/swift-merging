#if canImport(SwiftData)
import Foundation
import SwiftData

/// Where a merge keeps what the store's history doesn't: each object's earlier values, as encoded snapshots.
///
/// - The **base** is the object as this device last read it from the store. It's the fallback when the
///   store's own report of a save is missing.
/// - The **agreed base** is the object as both this device and the sync service last held it: what the last
///   import brought, or what the last export sent. A synced change merges against it, since the other
///   device started from it, not from whatever this device has saved since.
/// - **Local saves** are snapshots this device saved and hasn't yet seen exported. A finished export makes
///   the latest one the agreed base.
///
/// Alongside them sits the history token they're current to.
@available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
@MainActor
public protocol MergeLedger: AnyObject {
    /// The last history transaction the bases include, or `nil` before the first pass.
    var token: DefaultHistoryToken? { get set }

    /// An object's base.
    func base(for id: PersistentIdentifier) -> Data?

    /// Sets an object's base, or removes it with `nil`.
    func setBase(_ base: Data?, for id: PersistentIdentifier)

    /// An object's agreed base.
    func agreedBase(for id: PersistentIdentifier) -> Data?

    /// Sets an object's agreed base, or removes it with `nil`, and drops its local saves, which the new
    /// agreed base supersedes.
    func setAgreedBase(_ base: Data?, for id: PersistentIdentifier)

    /// Notes a snapshot this device saved at `date`, to become the agreed base once it's exported.
    func recordLocalSave(_ snapshot: Data, for id: PersistentIdentifier, at date: Date)

    /// Makes each object's latest local save from `date` or before its agreed base, since an export that
    /// started then has sent it.
    func promoteLocalSaves(through date: Date)

    /// Makes an object's latest local save from `date` or before its agreed base, since the sync service
    /// confirmed it sent the object in an export that started then.
    func promoteLocalSaves(for id: PersistentIdentifier, through date: Date)

    /// Saves everything together.
    func save() throws
}

/// A local save waiting for an export.
struct PendingLocalSave: Codable {
    var date: Date
    var snapshot: Data
}

/// A ledger kept in memory, which starts over at every launch by reading the store once.
@available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
@MainActor
public final class InMemoryMergeLedger: MergeLedger {
    public var token: DefaultHistoryToken?
    // Keyed by `MergeRelationship.key`, so an identifier rebuilt from a key finds the same entry.
    private var bases: [String: Data] = [:]
    private var agreed: [String: Data] = [:]
    private var pending: [String: [PendingLocalSave]] = [:]

    public init() {}

    public func base(for id: PersistentIdentifier) -> Data? { bases[MergeRelationship.key(id)] }

    public func setBase(_ base: Data?, for id: PersistentIdentifier) { bases[MergeRelationship.key(id)] = base }

    public func agreedBase(for id: PersistentIdentifier) -> Data? { agreed[MergeRelationship.key(id)] }

    public func setAgreedBase(_ base: Data?, for id: PersistentIdentifier) {
        let key = MergeRelationship.key(id)
        agreed[key] = base
        pending[key] = nil
    }

    public func recordLocalSave(_ snapshot: Data, for id: PersistentIdentifier, at date: Date) {
        pending[MergeRelationship.key(id), default: []].append(PendingLocalSave(date: date, snapshot: snapshot))
    }

    public func promoteLocalSaves(through date: Date) {
        promote(&pending, into: &agreed, through: date)
    }

    public func promoteLocalSaves(for id: PersistentIdentifier, through date: Date) {
        promote(&pending, into: &agreed, through: date, only: MergeRelationship.key(id))
    }

    public func save() throws {}
}

/// A ledger kept in a file, so bases outlive the app's process.
@available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
@MainActor
public final class FileMergeLedger: MergeLedger {
    private struct Contents: Codable {
        var token: DefaultHistoryToken?
        // Keyed by `MergeRelationship.key`: a decoded `PersistentIdentifier` doesn't hash like the one it
        // was encoded from.
        var bases: [String: Data] = [:]
        var agreed: [String: Data] = [:]
        var pending: [String: [PendingLocalSave]] = [:]

        init() {}

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            token = try container.decodeIfPresent(DefaultHistoryToken.self, forKey: .token)
            bases = try container.decodeIfPresent([String: Data].self, forKey: .bases) ?? [:]
            agreed = try container.decodeIfPresent([String: Data].self, forKey: .agreed) ?? [:]
            pending = try container.decodeIfPresent([String: [PendingLocalSave]].self, forKey: .pending) ?? [:]
        }
    }

    private let url: URL
    private var contents: Contents

    /// A ledger in the file at `url`, read from it if it's there.
    public init(url: URL) throws {
        self.url = url
        if FileManager.default.fileExists(atPath: url.path) {
            contents = try JSONDecoder().decode(Contents.self, from: Data(contentsOf: url))
        } else {
            contents = Contents()
        }
    }

    public var token: DefaultHistoryToken? {
        get { contents.token }
        set { contents.token = newValue }
    }

    public func base(for id: PersistentIdentifier) -> Data? { contents.bases[MergeRelationship.key(id)] }

    public func setBase(_ base: Data?, for id: PersistentIdentifier) { contents.bases[MergeRelationship.key(id)] = base }

    public func agreedBase(for id: PersistentIdentifier) -> Data? { contents.agreed[MergeRelationship.key(id)] }

    public func setAgreedBase(_ base: Data?, for id: PersistentIdentifier) {
        let key = MergeRelationship.key(id)
        contents.agreed[key] = base
        contents.pending[key] = nil
    }

    public func recordLocalSave(_ snapshot: Data, for id: PersistentIdentifier, at date: Date) {
        contents.pending[MergeRelationship.key(id), default: []].append(PendingLocalSave(date: date, snapshot: snapshot))
    }

    public func promoteLocalSaves(through date: Date) {
        promote(&contents.pending, into: &contents.agreed, through: date)
    }

    public func promoteLocalSaves(for id: PersistentIdentifier, through date: Date) {
        promote(&contents.pending, into: &contents.agreed, through: date, only: MergeRelationship.key(id))
    }

    public func save() throws {
        try JSONEncoder().encode(contents).write(to: url, options: .atomic)
    }
}

/// Moves each object's latest pending save from `date` or before into `agreed`, and drops those saves. With
/// `only`, just that object's.
private func promote(_ pending: inout [String: [PendingLocalSave]], into agreed: inout [String: Data], through date: Date,
                     only: String? = nil) {
    for (key, saves) in pending where only == nil || only == key {
        let sent = saves.filter { $0.date <= date }
        guard let latest = sent.max(by: { $0.date < $1.date }) else { continue }
        agreed[key] = latest.snapshot
        let left = saves.filter { $0.date > date }
        pending[key] = left.isEmpty ? nil : left
    }
}
#endif
