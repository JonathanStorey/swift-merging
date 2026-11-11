#if canImport(SwiftData)
import Foundation
import SwiftData

extension ModelContext {
    /// The container's sync monitor, together with this context so it can save: `context.sync.activity`,
    /// `context.sync.status(of: note)`, `try await context.sync.saveAndWait()`.
    @MainActor
    public var sync: ContextSync { ContextSync(context: self, monitor: container.sync) }
}

/// A context's view of its container's `SyncMonitor`. It reads every monitor property, such as
/// `activity` or `pendingUploadCount`, and adds a save that waits for CloudKit.
@MainActor
@dynamicMemberLookup
public struct ContextSync {
    public let context: ModelContext
    public let monitor: SyncMonitor

    public subscript<Value>(dynamicMember keyPath: KeyPath<SyncMonitor, Value>) -> Value {
        monitor[keyPath: keyPath]
    }

    /// Where `model` stands with iCloud. See `SyncMonitor.status(of:)`.
    public func status(of model: some PersistentModel) -> SyncStatus {
        monitor.status(of: model)
    }

    /// Whether the server has every one of `models` as this device last saved it.
    public func isSynced(_ models: [any PersistentModel]) -> Bool {
        monitor.isSynced(models)
    }

    /// Saves, then waits until CloudKit confirms the server has everything the save inserted or changed.
    ///
    /// Saving is what starts an upload, so this is as close to "sync now" as public API allows. A save of
    /// deletions only waits for the export that follows it. Throws only what `save()` throws.
    public func saveAndWait(timeout: Duration = .seconds(60)) async throws -> SyncWaitResult {
        let models = context.insertedModelsArray + context.changedModelsArray
        let deletes = !context.deletedModelsArray.isEmpty
        let date = Date.now
        try context.save()
        if !models.isEmpty {
            // Read after the save, which gives inserted models their permanent identifiers.
            return await monitor.waitForUpload(of: models, savedAt: date, timeout: timeout)
        }
        if deletes { return await monitor.waitForExport(startedAfter: date, timeout: timeout) }
        return .completed
    }

    /// See `SyncMonitor.waitForExport(startedAfter:timeout:)`.
    public func waitForExport(startedAfter date: Date, timeout: Duration = .seconds(30)) async -> SyncWaitResult {
        await monitor.waitForExport(startedAfter: date, timeout: timeout)
    }

    /// See `SyncMonitor.waitForImport(finishedAfter:timeout:)`.
    public func waitForImport(finishedAfter date: Date = .now, timeout: Duration = .seconds(30)) async -> SyncWaitResult {
        await monitor.waitForImport(finishedAfter: date, timeout: timeout)
    }

    /// See `SyncMonitor.waitForSync(timeout:)`.
    public func waitForSync(timeout: Duration = .seconds(60)) async -> SyncWaitResult {
        await monitor.waitForSync(timeout: timeout)
    }

    /// See `SyncMonitor.waitForUpload(of:savedAt:timeout:)`.
    public func waitForUpload(of models: [any PersistentModel], savedAt date: Date,
                              timeout: Duration = .seconds(60)) async -> SyncWaitResult {
        await monitor.waitForUpload(of: models, savedAt: date, timeout: timeout)
    }
}
#endif
