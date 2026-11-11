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

/// Why CloudKit couldn't sync, in terms an app can act on.
public enum SyncProblem: Error, Sendable, Equatable {
    /// No iCloud account is signed in, or it can't be used.
    case notSignedIn
    /// The user's iCloud storage is full.
    case quotaExceeded
    /// The device is offline or the connection failed.
    case networkUnavailable
    /// CloudKit asked to retry later. It retries on its own.
    case serverBusy
    /// Anything else, with the error's description.
    case other(String)

    /// Whether CloudKit retries on its own, so waiting is still worthwhile.
    public var isTransient: Bool {
        switch self {
        case .networkUnavailable, .serverBusy: true
        case .notSignedIn, .quotaExceeded, .other: false
        }
    }

    /// A short description for display.
    public var message: String {
        switch self {
        case .notSignedIn: "Sign in to iCloud to sync."
        case .quotaExceeded: "iCloud storage is full."
        case .networkUnavailable: "Offline. Changes will sync when the connection returns."
        case .serverBusy: "iCloud is busy. Sync will retry shortly."
        case .other(let description): description
        }
    }

    /// The problem an error describes. A partial failure is described by its first item's error.
    public init(_ error: any Error) {
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
        case .networkUnavailable, .networkFailure: self = .networkUnavailable
        case .serviceUnavailable, .requestRateLimited, .zoneBusy: self = .serverBusy
        default: self = .other(ckError.localizedDescription)
        }
    }
}

/// The iCloud account's state, as CloudKit reports it.
public enum AccountStatus: Sendable, Equatable {
    /// Not checked yet, or no CloudKit container is known to check.
    case unknown
    case available
    case noAccount
    case restricted
    case temporarilyUnavailable
    case couldNotDetermine

    init(_ status: CKAccountStatus) {
        switch status {
        case .available: self = .available
        case .noAccount: self = .noAccount
        case .restricted: self = .restricted
        case .temporarilyUnavailable: self = .temporarilyUnavailable
        case .couldNotDetermine: self = .couldNotDetermine
        @unknown default: self = .couldNotDetermine
        }
    }
}

/// A CloudKit setup, import or export, starting or finishing.
public struct SyncEvent: Sendable, Equatable {
    public enum Kind: Sendable, Hashable {
        case setup
        case `import`
        case export
    }

    public var kind: Kind
    public var startDate: Date
    /// When it finished, or `nil` while it's running.
    public var endDate: Date?
    public var succeeded: Bool
    /// Why it failed, if it did.
    public var problem: SyncProblem?

    public init(kind: Kind, startDate: Date, endDate: Date? = nil, succeeded: Bool = false, problem: SyncProblem? = nil) {
        self.kind = kind
        self.startDate = startDate
        self.endDate = endDate
        self.succeeded = succeeded
        self.problem = problem
    }

    public var isFinished: Bool { endDate != nil }
}

/// How a wait for CloudKit ended.
public enum SyncWaitResult: Sendable, Equatable {
    /// What it waited for happened.
    case completed
    /// CloudKit reported a problem it won't fix by retrying.
    case failed(SyncProblem)
    /// Time ran out first. `waiting` is how many objects were still waiting to upload, where that applies.
    case timedOut(waiting: Int)
    /// The store isn't syncing with CloudKit, so there was nothing to wait for.
    case notSyncing
}
#endif
