#if canImport(SwiftData)
import Foundation
import SwiftData

extension ModelContext {
    /// The sync monitor of the context's container, the same one every context on it shares.
    @MainActor
    public var sync: SyncMonitor { container.sync }

    /// Saves, then waits for CloudKit: with `.upload`, until the server confirms everything the save
    /// inserted or changed, and with `.download`, until the next download finishes too.
    ///
    /// Saving is what starts an upload, so this is as close to "sync now" as public API allows. A save of
    /// deletions only waits for the upload that follows it. Throws what `save()` throws, or `SyncError`.
    @MainActor
    public func save(waitingFor direction: SyncDirection, timeout: Duration = .seconds(60)) async throws {
        let monitor = sync
        let models = insertedModelsArray + changedModelsArray
        let deletes = !deletedModelsArray.isEmpty
        let date = Date.now
        let deadline = ContinuousClock.now.advanced(by: timeout)
        try save()
        if !models.isEmpty {
            // Read after the save, which gives inserted models their permanent identifiers.
            let keys = models.compactMap { StoreRecords.key(of: $0.persistentModelID) }
            try await monitor.wait(forKeys: keys, savedAt: date, timeout: timeout)
        } else if deletes {
            try await monitor.wait(for: .upload, after: date, timeout: timeout)
        }
        if direction == .download {
            try await monitor.wait(for: .download, after: date, timeout: ContinuousClock.now.duration(to: deadline))
        }
    }
}
#endif
