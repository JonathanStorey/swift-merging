#if canImport(SwiftData)
import CoreData
import Foundation
@testable import Persistence
import SwiftData
import Observation
import Testing

final class Changed: @unchecked Sendable {
    var value = false
}

/// The ledger reading real saves: SwiftData's, the app's Core Data saves, and rows saved as CloudKit does.
@Suite struct SaveTrackingTests {
    @Test func aSwiftDataSaveMarksTheObjectPending() throws {
        let ledger = SyncLedger(persists: false)
        ledger.startObserving()
        let fixture = try ModelFixture()
        ledger.record(cloudStores: [fixture.store])

        let context = ModelContext(fixture.container)
        let item = Item("first", tags: ["a"])
        context.insert(item)
        try context.save()

        let key = try #require(StoreRecords.key(of: item.persistentModelID))
        #expect(StoreRecords.store(ofKey: key) == fixture.store)
        guard case .pending = ledger.status(ofKey: key) else {
            Issue.record("Expected pending, got \(ledger.status(ofKey: key))")
            return
        }
    }

    @MainActor
    @Test func aModelsSyncStatusReadsTheSharedLedger() throws {
        SyncLedger.start(defaultsSuite: freshSuite())
        let fixture = try ModelFixture()
        let context = ModelContext(fixture.container)
        let item = Item("first")
        context.insert(item)
        #expect(item.syncStatus == .unsaved)

        try context.save()
        #expect(item.syncStatus == .localOnly)

        SyncLedger.shared.record(cloudStores: [fixture.store])
        guard case .pending = item.syncStatus else {
            Issue.record("Expected pending, got \(item.syncStatus)")
            return
        }
        item.name = "second"
        #expect(item.syncStatus == .unsaved)
        // One monitor per container, whichever context asks, and it sees the store syncing.
        #expect(context.sync === fixture.container.sync)
        #expect(context.sync.activity == .idle)
        #expect(context.sync.pending == 1)
    }

    @MainActor
    @Test func syncStatusIsObservable() async throws {
        SyncLedger.start(defaultsSuite: freshSuite())
        let fixture = try ModelFixture()
        let context = ModelContext(fixture.container)
        let item = Item("first")
        context.insert(item)
        try context.save()

        let changed = Changed()
        withObservationTracking { _ = item.syncStatus } onChange: { changed.value = true }
        SyncLedger.shared.record(cloudStores: [fixture.store])
        // The signal changes on the main queue, after the ledger does.
        try await Task.sleep(for: .milliseconds(100))
        #expect(changed.value)
    }

    @Test func cloudKitClearingNeedsUploadMarksTheObjectSynced() throws {
        let ledger = SyncLedger(persists: false)
        ledger.startObserving()
        let mirror = try MirrorFixture()
        let item = try mirror.saveItem()
        let key = StoreRecords.key(of: item)

        let row = try mirror.saveRow(for: item, needsUpload: true)
        // A metadata row marks its store as one that syncs.
        #expect(ledger.isCloudStore(mirror.store))
        guard case .pending = ledger.status(ofKey: key) else {
            Issue.record("Expected pending, got \(ledger.status(ofKey: key))")
            return
        }

        try mirror.saveRow(for: item, needsUpload: false, row: row)
        #expect(ledger.status(ofKey: key).isSynced)
    }

    @Test func anImportMarksTheObjectSynced() throws {
        let ledger = SyncLedger(persists: false)
        ledger.startObserving()
        let mirror = try MirrorFixture()
        ledger.record(cloudStores: [mirror.store])
        let item = try mirror.saveItem(author: StoreRecords.importAuthor)
        #expect(ledger.status(ofKey: StoreRecords.key(of: item)).isSynced)
    }

    @Test func theRowNamesTheObjectByItsURI() throws {
        let mirror = try MirrorFixture()
        let item = try mirror.saveItem()
        let row = try mirror.saveRow(for: item, needsUpload: false)
        let found = try #require(StoreRecords.syncedObject(of: row))
        #expect(found.key == StoreRecords.key(of: item))
        #expect(found.store == mirror.store)
        #expect(!found.needsUpload)
    }
}
#endif
