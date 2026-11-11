#if canImport(SwiftData)
import Foundation
import SwiftData

extension ModelContext {
    /// Where `model` stands with iCloud: unsaved, waiting to upload, or synced, as far as this device has
    /// seen since tracking started.
    ///
    /// Tracking starts with `SyncTracking.start()` or the first `syncMonitor`, so start it at launch. An
    /// object no save or sync has touched since then reads `.unknown`.
    public func syncStatus(of model: some PersistentModel) -> SyncStatus {
        if model.hasChanges { return .unsaved }
        guard let key = StoreRecords.key(of: model.persistentModelID) else { return .unknown }
        return SyncLedger.shared.status(ofKey: key)
    }

    /// Whether the server has every one of `models` as this device last saved it.
    public func isSynced(_ models: [any PersistentModel]) -> Bool {
        models.allSatisfy { syncStatus(of: $0).isSynced }
    }

    /// The sync monitor of the context's container.
    @MainActor
    public var syncMonitor: SyncMonitor { container.syncMonitor }

    /// Saves, then waits until CloudKit confirms the server has everything the save inserted or changed.
    ///
    /// Saving is what starts an upload, so this is as close to "sync now" as public API allows. A save of
    /// deletions only waits for the export that follows it. Throws only what `save()` throws.
    @MainActor
    public func saveAndWaitForUpload(timeout: Duration = .seconds(60)) async throws -> SyncWaitResult {
        let monitor = syncMonitor
        let models = insertedModelsArray + changedModelsArray
        let deletes = !deletedModelsArray.isEmpty
        let date = Date.now
        try save()
        if !models.isEmpty {
            // Read after the save, which gives inserted models their permanent identifiers.
            return await monitor.waitForUpload(of: models, savedAt: date, timeout: timeout)
        }
        if deletes { return await monitor.waitForExport(startedAfter: date, timeout: timeout) }
        return .completed
    }
}
#endif
