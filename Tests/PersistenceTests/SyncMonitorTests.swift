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
        #expect(monitor.activity == .off)

        let uploadID = UUID(), downloadID = UUID()
        let start = Date.now
        monitor.record(SyncEvent(kind: .download, startDate: start), id: downloadID, store: fixture.store)
        #expect(monitor.activity == .downloading)
        monitor.record(SyncEvent(kind: .upload, startDate: start), id: uploadID, store: fixture.store)
        #expect(monitor.activity == .uploading)

        let end = start.addingTimeInterval(1)
        monitor.record(SyncEvent(kind: .upload, startDate: start, endDate: end, succeeded: true), id: uploadID, store: fixture.store)
        #expect(monitor.activity == .downloading)
        #expect(monitor.lastSynced == end)
        let later = end.addingTimeInterval(1)
        monitor.record(SyncEvent(kind: .download, startDate: start, endDate: later, succeeded: true), id: downloadID, store: fixture.store)
        #expect(monitor.activity == .idle)
        #expect(monitor.lastSynced == later)
    }

    @Test func otherStoresAreIgnored() {
        monitor.record(SyncEvent(kind: .download, startDate: .now), id: UUID(), store: "another store")
        #expect(monitor.activity == .off)
    }

    @Test func anErrorLastsUntilTheSameKindSucceeds() {
        let start = Date.now
        monitor.record(SyncEvent(kind: .upload, startDate: start, endDate: start, error: .quotaExceeded), id: UUID(), store: fixture.store)
        #expect(monitor.error == .quotaExceeded)
        monitor.record(SyncEvent(kind: .download, startDate: start, endDate: start, succeeded: true), id: UUID(), store: fixture.store)
        #expect(monitor.error == .quotaExceeded)
        monitor.record(SyncEvent(kind: .upload, startDate: start, endDate: start, succeeded: true), id: UUID(), store: fixture.store)
        #expect(monitor.error == nil)
    }

    @Test func eventsStreamAsTheyHappen() async {
        let stream = monitor.events
        let event = SyncEvent(kind: .download, startDate: .now)
        monitor.record(event, id: UUID(), store: fixture.store)
        var iterator = stream.makeAsyncIterator()
        #expect(await iterator.next() == event)
    }

    @Test func waitingForAnUploadReturnsWhenALaterOneFinishes() async throws {
        let monitor = monitor, store = fixture.store
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            monitor.record(SyncEvent(kind: .upload, startDate: .now, endDate: .now, succeeded: true), id: UUID(), store: store)
        }
        try await monitor.wait(for: .upload, timeout: .seconds(5))
    }

    @Test func waitingForAnUploadIgnoresOneThatStartedEarlier() async {
        let before = Date.now.addingTimeInterval(-1)
        monitor.record(SyncEvent(kind: .upload, startDate: before, endDate: .now, succeeded: true), id: UUID(), store: fixture.store)
        await #expect(throws: SyncError.timedOut) {
            try await monitor.wait(for: .upload, timeout: .milliseconds(300))
        }
    }

    @Test func waitingStopsOnALastingFailure() async {
        let monitor = monitor, store = fixture.store
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(100))
            monitor.record(SyncEvent(kind: .upload, startDate: .now, endDate: .now, error: .notSignedIn), id: UUID(), store: store)
        }
        await #expect(throws: SyncError.notSignedIn) {
            try await monitor.wait(for: .upload, timeout: .seconds(5))
        }
    }

    @Test func waitingForObjectsReturnsOnceEachIsConfirmed() async throws {
        let key = "x-coredata://\(fixture.store)/Item/p1"
        ledger.record(changed: [key], cloudStores: [fixture.store])
        let ledger = ledger
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            ledger.record(confirmed: [key])
        }
        try await monitor.wait(forKeys: [key], savedAt: nil, timeout: .seconds(5))
    }

    @Test func waitingForObjectsTimesOut() async {
        let key = "x-coredata://\(fixture.store)/Item/p1"
        ledger.record(changed: [key], cloudStores: [fixture.store])
        await #expect(throws: SyncError.timedOut) {
            try await monitor.wait(forKeys: [key], savedAt: nil, timeout: .milliseconds(300))
        }
    }

    @Test func waitingOnALocalStoreIsNotEnabled() async {
        let key = "x-coredata://\(fixture.store)/Item/p1"
        ledger.record(changed: [key])
        await #expect(throws: SyncError.notEnabled) {
            try await monitor.wait(forKeys: [key], savedAt: nil, timeout: .milliseconds(300))
        }
        await #expect(throws: SyncError.notEnabled) {
            try await monitor.wait()
        }
    }
}
#endif
