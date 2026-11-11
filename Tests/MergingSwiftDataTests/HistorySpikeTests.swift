#if canImport(SwiftData)
import Foundation
import SwiftData
import Testing

/// What SwiftData itself does, which the merge relies on. A failure here means a design assumption is
/// wrong, not that the merge has a bug.
@MainActor
@Suite struct HistorySpikeTests {
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func historyRecordsTheAuthorAndOnlyTheChangedAttributes() throws {
        let fixture = try Fixture()
        try fixture.theirEdit { $0.title = "Renamed" }

        let transactions = try ModelContext(fixture.container).fetchHistory(HistoryDescriptor<DefaultHistoryTransaction>())
        let last = try #require(transactions.last)
        #expect(last.author == "sync")
        let updates = last.changes.compactMap { change -> DefaultHistoryUpdate<Note>? in
            guard case .update(let update) = change else { return nil }
            return update as? DefaultHistoryUpdate<Note>
        }
        try #require(updates.count == 1)
        print("Spike: updatedAttributes =", updates[0].updatedAttributes)
        #expect(updates[0].changedPersistentIdentifier == fixture.id)
        #expect(updates[0].updatedAttributes.contains(\Note.title))
        #expect(updates[0].updatedAttributes.count == 1)
    }

    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func historyTokensRoundTripThroughCodable() throws {
        let fixture = try Fixture()
        let token = try #require(try ModelContext(fixture.container).fetchHistory(HistoryDescriptor<DefaultHistoryTransaction>()).last?.token)
        let decoded = try JSONDecoder().decode(DefaultHistoryToken.self, from: JSONEncoder().encode(token))
        #expect(decoded == token)
    }

    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func unsavedEditsSurviveAnotherContextsSave() throws {
        let fixture = try Fixture()
        fixture.note.title = "Mine"
        try fixture.theirEdit { $0.title = "Theirs"; $0.color = "blue" }

        print("Spike: after their save, main sees title =", fixture.note.title, "color =", fixture.note.color, "hasChanges =", fixture.note.hasChanges)
        #expect(fixture.note.title == "Mine")
        #expect(fixture.note.hasChanges)
    }

    /// Without the merge, a property both sides changed keeps whichever saved last, so one increment is lost.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func withoutMergingTheLastSaveWinsAProperty() throws {
        let fixture = try Fixture()
        fixture.note.likes += 1
        try fixture.theirEdit { $0.likes += 2 }
        try fixture.container.mainContext.save()
        print("Spike: likes after both saved, unmerged =", try fixture.saved().likes)
        #expect(try fixture.saved().likes == 1)
    }

    /// Found by this spike: a save writes the whole object, so without the merge even a property only the
    /// other side changed goes back to what the main context last read. The snapshot has to list every
    /// stored property for that reason.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func withoutMergingOurSaveRevertsAPropertyOnlyTheyChanged() throws {
        let fixture = try Fixture()
        fixture.note.title = "Mine"
        try fixture.theirEdit { $0.color = "blue" }
        try fixture.container.mainContext.save()
        let saved = try fixture.saved()
        #expect(saved.title == "Mine")
        #expect(saved.color == "red")
    }

    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func changesMadeDuringWillSaveAreSaved() throws {
        let fixture = try Fixture()
        let main = fixture.container.mainContext
        nonisolated(unsafe) let note = fixture.note
        let observer = NotificationCenter.default.addObserver(forName: ModelContext.willSave, object: main, queue: nil) { _ in
            MainActor.assumeIsolated { note.color = "green" }
        }
        defer { NotificationCenter.default.removeObserver(observer) }
        note.title = "Mine"
        try main.save()
        #expect(try fixture.saved().color == "green")
    }
}
#endif
