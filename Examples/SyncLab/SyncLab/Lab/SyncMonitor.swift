import CoreData
import Foundation
import Observation

/// CloudKit's imports and exports, per store, from the container's own event notifications.
@MainActor @Observable
final class SyncMonitor {
    static let shared = SyncMonitor()

    struct Activity: Equatable {
        var settingUp = false
        var importing = false
        var exporting = false
        /// When the latest successful import and export started, so a wait can ask for one that began after
        /// a given save.
        var lastImportStart: Date?
        var lastExportStart: Date?
        var lastError: String?
    }

    private(set) var activity: [String: Activity] = [:]
    /// Called for each finished event, with the store and a line to log.
    @ObservationIgnored var onEvent: ((String, String) -> Void)?
    @ObservationIgnored private var observer: (any NSObjectProtocol)?

    func start() {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(forName: NSPersistentCloudKitContainer.eventChangedNotification,
                                                          object: nil, queue: .main) { note in
            guard let event = note.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                    as? NSPersistentCloudKitContainer.Event else { return }
            let store = event.storeIdentifier
            let type = event.type
            let start = event.startDate
            let end = event.endDate
            let succeeded = event.succeeded
            let error = event.error?.localizedDescription
            MainActor.assumeIsolated {
                SyncMonitor.shared.record(store: store, type: type, start: start, end: end, succeeded: succeeded, error: error)
            }
        }
    }

    func activity(for store: String?) -> Activity {
        store.flatMap { activity[$0] } ?? Activity()
    }

    /// Whether the store finished an export that started at or after `date`.
    func exported(_ store: String?, since date: Date) -> Bool {
        (activity(for: store).lastExportStart ?? .distantPast) >= date
    }

    /// Whether the store finished an import that started at or after `date`.
    func imported(_ store: String?, since date: Date) -> Bool {
        (activity(for: store).lastImportStart ?? .distantPast) >= date
    }

    private func record(store: String, type: NSPersistentCloudKitContainer.EventType, start: Date, end: Date?,
                        succeeded: Bool, error: String?) {
        var current = activity[store] ?? Activity()
        let running = end == nil
        let name: String
        switch type {
        case .setup:
            current.settingUp = running
            name = "setup"
        case .import:
            current.importing = running
            if !running, succeeded { current.lastImportStart = start }
            name = "import"
        case .export:
            current.exporting = running
            if !running, succeeded { current.lastExportStart = start }
            name = "export"
        @unknown default:
            name = "event"
        }
        if !running {
            current.lastError = succeeded ? nil : (error ?? "\(name) failed")
            onEvent?(store, succeeded ? "\(name) finished" : "\(name) failed: \(error ?? "unknown error")")
        }
        activity[store] = current
    }
}
