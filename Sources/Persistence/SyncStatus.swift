#if canImport(SwiftData)
import CloudKit
import Foundation

/// Where one object stands with iCloud.
public enum SyncStatus: Sendable, Equatable {
    /// It has changes that haven't been saved to the store, so there's nothing to upload yet.
    case unsaved
    /// Its store hasn't been seen syncing with CloudKit, so it stays on this device.
    case localOnly
    /// Saved, and waiting for CloudKit to upload it, since `since`.
    case pending(since: Date)
    /// The server has this version: CloudKit uploaded it or downloaded it at `at`.
    case synced(at: Date)
    /// Its store syncs, but this object hasn't been seen saved or synced since tracking began.
    case unknown

    /// Whether the server is known to have this version.
    public var isSynced: Bool {
        if case .synced = self { true } else { false }
    }

    /// An SF Symbol for the status.
    public var symbolName: String {
        switch self {
        case .unsaved: "pencil.circle"
        case .localOnly: "icloud.slash"
        case .pending: "arrow.triangle.2.circlepath.icloud"
        case .synced: "checkmark.icloud"
        case .unknown: "icloud"
        }
    }
}

/// Which way data moves between this device and iCloud.
public enum SyncDirection: Sendable, Hashable {
    case upload
    case download
}

/// Why CloudKit couldn't sync, or why a wait ended without what it waited for.
public enum SyncError: Error, Sendable, Equatable {
    /// The wait's timeout passed first.
    case timedOut
    /// The store isn't syncing with CloudKit, so there's nothing to wait for.
    case notEnabled
    /// No iCloud account is signed in, or it can't be used.
    case notSignedIn
    /// The user's iCloud storage is full.
    case quotaExceeded
    /// The device is offline or the connection failed. CloudKit retries on its own.
    case offline
    /// CloudKit asked to retry later. It retries on its own.
    case serverBusy
    /// Anything else, with the error's description.
    case other(String)

    /// Whether CloudKit retries on its own, so waiting is still worthwhile.
    public var isTransient: Bool {
        switch self {
        case .offline, .serverBusy: true
        default: false
        }
    }

    /// The error a CloudKit failure means. A partial failure is described by its first item's error.
    public init(_ error: any Error) {
        if let error = error as? SyncError {
            self = error
            return
        }
        guard let ckError = error as? CKError else {
            self = .other(error.localizedDescription)
            return
        }
        if ckError.code == .partialFailure, let first = ckError.partialErrorsByItemID?.values.first {
            self.init(first)
            return
        }
        switch ckError.code {
        case .notAuthenticated, .accountTemporarilyUnavailable: self = .notSignedIn
        case .quotaExceeded: self = .quotaExceeded
        case .networkUnavailable, .networkFailure: self = .offline
        case .serviceUnavailable, .requestRateLimited, .zoneBusy: self = .serverBusy
        default: self = .other(ckError.localizedDescription)
        }
    }
}

extension SyncError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .timedOut: "iCloud didn't confirm in time."
        case .notEnabled: "iCloud sync isn't on."
        case .notSignedIn: "Sign in to iCloud to sync."
        case .quotaExceeded: "iCloud storage is full."
        case .offline: "Offline. Changes will sync when the connection returns."
        case .serverBusy: "iCloud is busy. Sync will retry shortly."
        case .other(let description): description
        }
    }
}

/// A CloudKit setup, download or upload, starting or finishing.
public struct SyncEvent: Sendable, Equatable {
    public enum Kind: Sendable, Hashable {
        case setup
        case download
        case upload
    }

    public var kind: Kind
    public var startDate: Date
    /// When it finished, or `nil` while it's running.
    public var endDate: Date?
    public var succeeded: Bool
    /// Why it failed, if it did.
    public var error: SyncError?

    public init(kind: Kind, startDate: Date, endDate: Date? = nil, succeeded: Bool = false, error: SyncError? = nil) {
        self.kind = kind
        self.startDate = startDate
        self.endDate = endDate
        self.succeeded = succeeded
        self.error = error
    }

    public var isFinished: Bool { endDate != nil }
}

extension SyncDirection {
    var eventKind: SyncEvent.Kind {
        switch self {
        case .upload: .upload
        case .download: .download
        }
    }
}
#endif
