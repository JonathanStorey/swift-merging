#if canImport(SwiftData) && canImport(SwiftUI)
import SwiftUI

extension Label where Title == Text, Icon == Image {
    /// An iCloud symbol and a caption for the monitor's state, such as "Up to date", "Uploading",
    /// "3 pending", or the error.
    @MainActor
    public init(_ sync: SyncMonitor) {
        self.init(sync.caption, systemImage: sync.symbolName)
    }
}

extension Image {
    /// The SF Symbol for an object's sync status.
    public init(_ status: SyncStatus) {
        self.init(systemName: status.symbolName)
    }
}

extension SyncMonitor {
    /// A short caption for the monitor's state.
    public var caption: String {
        if let error { return error.localizedDescription }
        if account == .noAccount || account == .restricted { return "iCloud unavailable" }
        switch activity {
        case .off: return "Not syncing"
        case .uploading: return "Uploading"
        case .downloading: return "Downloading"
        case .preparing: return "Preparing iCloud"
        case .idle: return pending > 0 ? "\(pending) pending" : "Up to date"
        }
    }

    /// An SF Symbol for the monitor's state.
    public var symbolName: String {
        if error != nil { return "exclamationmark.icloud" }
        if account == .noAccount || account == .restricted { return "icloud.slash" }
        switch activity {
        case .off: return "icloud.slash"
        case .uploading: return "icloud.and.arrow.up"
        case .downloading: return "icloud.and.arrow.down"
        case .preparing: return "icloud"
        case .idle: return pending > 0 ? "arrow.triangle.2.circlepath.icloud" : "checkmark.icloud"
        }
    }
}
#endif
