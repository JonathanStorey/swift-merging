#if canImport(SwiftData) && canImport(SwiftUI)
import SwiftData
import SwiftUI

/// A small iCloud symbol and caption for a container's sync state, such as for a toolbar.
public struct SyncIndicator: View {
    private let monitor: SyncMonitor
    private let showsCaption: Bool

    public init(_ monitor: SyncMonitor, showsCaption: Bool = true) {
        self.monitor = monitor
        self.showsCaption = showsCaption
    }

    public var body: some View {
        Label(caption, systemImage: monitor.symbolName)
            .labelStyle(SyncIndicatorStyle(showsCaption: showsCaption))
            .accessibilityLabel(caption)
    }

    private var caption: String {
        if let problem = monitor.problem { return problem.message }
        switch monitor.accountStatus {
        case .noAccount, .restricted: return "iCloud unavailable"
        default: break
        }
        switch monitor.activity {
        case .exporting: return "Uploading"
        case .importing: return "Downloading"
        case .settingUp: return "Preparing iCloud"
        case .idle:
            if !monitor.isSyncing { return "Not syncing" }
            if monitor.pendingUploadCount > 0 { return "\(monitor.pendingUploadCount) waiting to upload" }
            return "Up to date"
        }
    }
}

extension View {
    /// Puts `container`'s sync monitor in the environment, for `@Environment(SyncMonitor.self)` below.
    @MainActor
    public func syncMonitor(for container: ModelContainer) -> some View {
        environment(container.sync)
    }
}

private struct SyncIndicatorStyle: LabelStyle {
    let showsCaption: Bool

    func makeBody(configuration: Configuration) -> some View {
        if showsCaption {
            Label(configuration)
        } else {
            configuration.icon
        }
    }
}

extension SyncMonitor {
    /// An SF Symbol for the monitor's state.
    public var symbolName: String {
        if problem != nil { return "exclamationmark.icloud" }
        if accountStatus == .noAccount || accountStatus == .restricted { return "icloud.slash" }
        switch activity {
        case .exporting: return "icloud.and.arrow.up"
        case .importing: return "icloud.and.arrow.down"
        case .settingUp: return "icloud"
        case .idle:
            if !isSyncing { return "icloud.slash" }
            return pendingUploadCount > 0 ? "arrow.triangle.2.circlepath.icloud" : "checkmark.icloud"
        }
    }
}
#endif
