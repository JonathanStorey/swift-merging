#if canImport(SwiftData)
import Foundation
import SwiftData

/// Where a merge keeps each object's base, the merged properties as last saved, since the store's history
/// records which properties changed but not what they were. Alongside them sits the history token the
/// bases are current to.
@available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
@MainActor
public protocol MergeLedger: AnyObject {
    /// The last history transaction the bases include, or `nil` before the first pass.
    var token: DefaultHistoryToken? { get set }

    /// An object's base, as an encoded snapshot.
    func base(for id: PersistentIdentifier) -> Data?

    /// Sets an object's base, or removes it with `nil`.
    func setBase(_ base: Data?, for id: PersistentIdentifier)

    /// Saves the token and bases together.
    func save() throws
}

/// A ledger kept in memory, which starts over at every launch by reading the store once.
@available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
@MainActor
public final class InMemoryMergeLedger: MergeLedger {
    public var token: DefaultHistoryToken?
    private var bases: [PersistentIdentifier: Data] = [:]

    public init() {}

    public func base(for id: PersistentIdentifier) -> Data? { bases[id] }

    public func setBase(_ base: Data?, for id: PersistentIdentifier) { bases[id] = base }

    public func save() throws {}
}

/// A ledger kept in a file, so bases outlive the app's process.
@available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
@MainActor
public final class FileMergeLedger: MergeLedger {
    private struct Contents: Codable {
        var token: DefaultHistoryToken?
        var bases: [PersistentIdentifier: Data] = [:]
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

    public func base(for id: PersistentIdentifier) -> Data? { contents.bases[id] }

    public func setBase(_ base: Data?, for id: PersistentIdentifier) { contents.bases[id] = base }

    public func save() throws {
        try JSONEncoder().encode(contents).write(to: url, options: .atomic)
    }
}
#endif
