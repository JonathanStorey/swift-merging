#if canImport(SwiftData)
import Foundation
import SwiftData

extension ModelContext {
    /// The sync monitor of the context's container, the same one every context on it shares.
    @MainActor
    public var sync: SyncMonitor { container.sync }

    /// Saves, then waits until CloudKit confirms the server has everything the save inserted or changed.
    ///
    /// Saving is what starts an upload, so this is as close to "sync now" as public API allows. A save of
    /// deletions only waits for the export that follows it. Throws only what `save()` throws.
    @MainActor
    public func saveAndWaitForUpload(timeout: Duration = .seconds(60)) async throws -> SyncWaitResult {
        let monitor = sync
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
