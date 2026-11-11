#if canImport(SwiftData)
import CloudKit
import CoreData
import Foundation
@testable import Persistence
import Testing

@Suite struct SyncLedgerTests {
    let store = UUID().uuidString
    var key: String { "x-coredata://\(store)/Item/p1" }

    @Test func aStoreNotSeenSyncingIsLocalOnly() {
        let ledger = SyncLedger(persists: false)
        ledger.record(changed: [key])
        #expect(ledger.status(ofKey: key) == .localOnly)
    }

    @Test func anObjectGoesFromUnknownToPendingToSynced() {
        let ledger = SyncLedger(persists: false)
        ledger.record(cloudStores: [store])
        #expect(ledger.status(ofKey: key) == .unknown)

        let saved = Date(timeIntervalSinceReferenceDate: 100)
        ledger.record(changed: [key], at: saved)
        #expect(ledger.status(ofKey: key) == .pending(since: saved))
        #expect(ledger.pendingCount(inStores: [store]) == 1)

        // A second save keeps the oldest date it's been waiting since.
        ledger.record(changed: [key], at: saved.addingTimeInterval(5))
        #expect(ledger.status(ofKey: key) == .pending(since: saved))

        let uploaded = saved.addingTimeInterval(10)
        ledger.record(confirmed: [key], at: uploaded)
        #expect(ledger.status(ofKey: key) == .synced(at: uploaded))
        #expect(ledger.pendingCount(inStores: [store]) == 0)
    }

    @Test func aDeletionForgetsTheObject() {
        let ledger = SyncLedger(persists: false)
        ledger.record(changed: [key], cloudStores: [store])
        ledger.record(deleted: [key])
        #expect(ledger.status(ofKey: key) == .unknown)
    }

    @Test func anUnsavedObjectHasNoStore() {
        let ledger = SyncLedger(persists: false)
        #expect(ledger.status(ofKey: "x-coredata:///Item/t1234") == .unsaved)
    }

    @Test func itSurvivesARelaunch() {
        let suite = freshSuite()
        let first = SyncLedger(defaultsSuite: suite)
        first.record(changed: [key], cloudStores: [store], at: Date(timeIntervalSinceReferenceDate: 7))

        let second = SyncLedger(defaultsSuite: suite)
        #expect(second.snapshot == first.snapshot)
        #expect(second.status(ofKey: key) == .pending(since: Date(timeIntervalSinceReferenceDate: 7)))
    }

    @Test func errorsComeFromCloudKitErrors() {
        #expect(SyncError(CKError(.notAuthenticated)) == .notSignedIn)
        #expect(SyncError(CKError(.quotaExceeded)) == .quotaExceeded)
        #expect(SyncError(CKError(.networkUnavailable)) == .offline)
        #expect(SyncError(CKError(.zoneBusy)).isTransient)
        #expect(!SyncError(CKError(.quotaExceeded)).isTransient)
    }
}
#endif
