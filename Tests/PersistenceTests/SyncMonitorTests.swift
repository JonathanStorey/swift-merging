#if canImport(SwiftData)
import Foundation
@testable import Persistence
import SwiftData
import Testing

@MainActor
@Suite struct SyncMonitorTests {
    let fixture: ModelFixture
    let ledger = SyncLedger(persists: false)
    let monitor: SyncMonitor

    init() throws {
        fixture = try ModelFixture()
        monitor = SyncMonitor(container: fixture.container, ledger: ledger, observes: false)
    }

    @Test func activityFollowsRunningEvents() {
        #expect(monitor.activity == .idle)
        #expect(!monitor.isSyncing)

        let exportID = UUID(), importID = UUID()
        let start = Date.now
        monitor.record(SyncEvent(kind: .import, startDate: start), id: importID, store: fixture.store)
        #expect(monitor.activity == .importing)
        #expect(monitor.isSyncing)
        monitor.record(SyncEvent(kind: .export, startDate: start), id: exportID, store: fixture.store)
        #expect(monitor.activity == .exporting)

        let end = start.addingTimeInterval(1)
        monitor.record(SyncEvent(kind: .export, startDate: start, endDate: end, succeeded: true), id: exportID, store: fixture.store)
        #expect(monitor.activity == .importing)
        #expect(monitor.lastExport == end)
        monitor.record(SyncEvent(kind: .import, startDate: start, endDate: end, succeeded: true), id: importID, store: fixture.store)
        #expect(monitor.activity == .idle)
        #expect(monitor.lastImport == end)
    }

    @Test func otherStoresAreIgnored() {
        monitor.record(SyncEvent(kind: .import, startDate: .now), id: UUID(), store: "another store")
        #expect(monitor.activity == .idle)
    }

    @Test func aProblemLastsUntilTheSameKindSucceeds() {
        let start = Date.now
        monitor.record(SyncEvent(kind: .export, startDate: start, endDate: start, problem: .quotaExceeded), id: UUID(), store: fixture.store)
        #expect(monitor.problem == .quotaExceeded)
        monitor.record(SyncEvent(kind: .import, startDate: start, endDate: start, succeeded: true), id: UUID(), store: fixture.store)
        #expect(monitor.problem == .quotaExceeded)
        monitor.record(SyncEvent(kind: .export, startDate: start, endDate: start, succeeded: true), id: UUID(), store: fixture.store)
        #expect(monitor.problem == nil)
    }

    @Test func waitForExportReturnsWhenALaterExportFinishes() async {
        let saved = Date.now
        let monitor = monitor, fixture = fixture
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            monitor.record(SyncEvent(kind: .export, startDate: .now, endDate: .now, succeeded: true), id: UUID(), store: fixture.store)
        }
        #expect(await monitor.waitForExport(startedAfter: saved, timeout: .seconds(5)) == .completed)
    }

    @Test func waitForExportIgnoresAnExportThatStartedBeforeTheSave() async {
        let before = Date.now
        let saved = before.addingTimeInterval(1)
        monitor.record(SyncEvent(kind: .export, startDate: before, endDate: saved, succeeded: true), id: UUID(), store: fixture.store)
        #expect(await monitor.waitForExport(startedAfter: saved, timeout: .milliseconds(300)) == .timedOut(waiting: 0))
    }

    @Test func waitForExportStopsOnALastingFailure() async {
        let saved = Date.now
        monitor.record(SyncEvent(kind: .export, startDate: saved, endDate: saved, problem: .notSignedIn), id: UUID(), store: fixture.store)
        #expect(await monitor.waitForExport(startedAfter: saved, timeout: .seconds(5)) == .failed(.notSignedIn))
    }

    @Test func waitForUploadReturnsOnceEveryObjectIsConfirmed() async {
        let key = "x-coredata://\(fixture.store)/Item/p1"
        let saved = Date.now
        ledger.record(changed: [key], cloudStores: [fixture.store], at: saved)
        let ledger = ledger
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            ledger.record(confirmed: [key])
        }
        #expect(await monitor.waitForUpload(ofKeys: [key], savedAt: saved, timeout: .seconds(5)) == .completed)
    }

    @Test func waitForUploadTimesOutWithWhatsWaiting() async {
        let key = "x-coredata://\(fixture.store)/Item/p1"
        ledger.record(changed: [key], cloudStores: [fixture.store])
        #expect(await monitor.waitForUpload(ofKeys: [key], savedAt: .now, timeout: .milliseconds(300)) == .timedOut(waiting: 1))
    }

    @Test func waitForUploadOfALocalStoreIsNotSyncing() async {
        let key = "x-coredata://\(fixture.store)/Item/p1"
        ledger.record(changed: [key])
        #expect(await monitor.waitForUpload(ofKeys: [key], savedAt: .now, timeout: .milliseconds(300)) == .notSyncing)
    }
}
#endif
