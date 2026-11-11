#if canImport(SwiftData)
import Foundation
import MergingSwiftData
import SwiftData
import Testing

@MainActor
@Suite struct MergeCoordinatorTests {
    /// Edits the note in the main context, unsaved, and in another context, saved, then merges and saves.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    func merge(ours: (Note) -> Void, theirs: (Note) -> Void, policy: MergeConflictPolicy = .keepOurs) throws -> (Fixture, Saved) {
        let fixture = try Fixture()
        let coordinator = try MergeCoordinator(container: fixture.container, types: [Note.self], conflictPolicy: policy)
        ours(fixture.note)
        try fixture.theirEdit(theirs)
        try coordinator.mergePendingChanges()
        try fixture.container.mainContext.save()
        try coordinator.mergePendingChanges()
        return (fixture, try fixture.saved())
    }

    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func bothIncrementsCount() throws {
        let (_, saved) = try merge(ours: { $0.likes += 1 }, theirs: { $0.likes += 2 })
        #expect(saved.likes == 3)
    }

    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func editsToDifferentWordsCombine() throws {
        let (_, saved) = try merge(ours: { $0.body = "the slow brown fox" }, theirs: { $0.body = "the quick brown dog" })
        #expect(saved.body == "the slow brown dog")
    }

    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func keepTheirsTakesTheirTitle() throws {
        let (_, saved) = try merge(ours: { $0.title = "Mine" }, theirs: { $0.title = "Theirs" })
        #expect(saved.title == "Theirs")
    }

    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func insertionsFromBothSidesAreKept() throws {
        let (_, saved) = try merge(ours: { $0.steps.append("cook") }, theirs: { $0.steps.append("serve") })
        #expect(saved.steps == ["prep", "cook", "serve"])
    }

    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func aPropertyOnlyTheyChangedComesThrough() throws {
        let (_, saved) = try merge(ours: { $0.title = "Mine" }, theirs: { $0.likes = 5 })
        #expect(saved.title == "Mine")
        #expect(saved.likes == 5)
    }

    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func aConflictKeepsOursByDefault() throws {
        let (_, saved) = try merge(ours: { $0.body = "the slow brown fox" }, theirs: { $0.body = "the fast brown fox" })
        #expect(saved.body == "the slow brown fox")
    }

    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func aConflictCanKeepTheirs() throws {
        let (_, saved) = try merge(ours: { $0.body = "the slow brown fox" }, theirs: { $0.body = "the fast brown fox" },
                                   policy: .keepTheirs)
        #expect(saved.body == "the fast brown fox")
    }

    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func theMergeLandsInTheMainContextBeforeItSaves() throws {
        let fixture = try Fixture()
        let coordinator = try MergeCoordinator(container: fixture.container, types: [Note.self])
        fixture.note.likes += 1
        try fixture.theirEdit { $0.likes += 2 }
        try coordinator.mergePendingChanges()
        #expect(fixture.note.likes == 3)
        #expect(fixture.note.hasChanges)
    }

    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func withNoUnsavedEditsTheirsStands() throws {
        let fixture = try Fixture()
        let coordinator = try MergeCoordinator(container: fixture.container, types: [Note.self])
        try fixture.theirEdit { $0.likes = 7 }
        try coordinator.mergePendingChanges()
        #expect(try fixture.saved().likes == 7)
    }

    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func mergesAgainAfterASecondRound() throws {
        let fixture = try Fixture()
        let coordinator = try MergeCoordinator(container: fixture.container, types: [Note.self])
        for _ in 0..<2 {
            fixture.note.likes += 1
            try fixture.theirEdit { $0.likes += 10 }
            try coordinator.mergePendingChanges()
            try fixture.container.mainContext.save()
            try coordinator.mergePendingChanges()
        }
        #expect(try fixture.saved().likes == 22)
    }

    /// The silent path: nothing calls the coordinator, and the main context's save merges first.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func enableMergingMergesOnSaveWithNoOtherCalls() throws {
        let fixture = try Fixture()
        try fixture.container.enableMerging(Note.self)
        fixture.note.likes += 1
        fixture.note.body = "the slow brown fox"
        try fixture.theirEdit { $0.likes += 2; $0.body = "the quick brown dog" }
        try fixture.container.mainContext.save()
        let saved = try fixture.saved()
        #expect(saved.likes == 3)
        #expect(saved.body == "the slow brown dog")
    }

    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func aFileLedgerKeepsBasesAcrossCoordinators() throws {
        let fixture = try Fixture()
        let url = FileManager.default.temporaryDirectory.appending(path: "ledger-\(UUID().uuidString).json")
        _ = try MergeCoordinator(container: fixture.container, types: [Note.self], ledger: FileMergeLedger(url: url))
        let reopened = try FileMergeLedger(url: url)
        #expect(reopened.token != nil)
        #expect(reopened.base(for: fixture.id) != nil)

        let coordinator = try MergeCoordinator(container: fixture.container, types: [Note.self], ledger: reopened)
        fixture.note.likes += 1
        try fixture.theirEdit { $0.likes += 2 }
        try coordinator.mergePendingChanges()
        #expect(fixture.note.likes == 3)
    }

    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func aDeletedObjectLeavesTheLedger() throws {
        let fixture = try Fixture()
        let coordinator = try MergeCoordinator(container: fixture.container, types: [Note.self])
        #expect(coordinator.ledger.base(for: fixture.id) != nil)
        let other = fixture.otherContext()
        other.delete(try fixture.note(in: other))
        try other.save()
        try coordinator.mergePendingChanges()
        #expect(coordinator.ledger.base(for: fixture.id) == nil)
    }
}
#endif
