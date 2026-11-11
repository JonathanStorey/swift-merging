#if canImport(SwiftData)
import Foundation
@testable import MergingSwiftData
import SwiftData
import Testing

/// The base as the store reports it while another context saves, and the merges that use it.
@MainActor
@Suite struct StoreCaptureTests {
    // MARK: - What the store reports (a failure here means an assumption about SwiftData is wrong)

    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func anIdentifiersKeyIsItsCoreDataURI() throws {
        let fixture = try Fixture()
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        print("Spike: encoded identifier =", String(decoding: try encoder.encode(fixture.id), as: UTF8.self))
        let key = MergeRelationship.key(fixture.id)
        print("Spike: key =", key)
        #expect(key.hasPrefix("x-coredata://"))
    }

    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func aKeyRebuildsAnIdentifierThatFindsItsObject() throws {
        let fixture = try Fixture()
        _ = MergeRelationship.key(fixture.id)
        let tag = try #require(fixture.note.tags.first)
        let tagKey = MergeRelationship.key(tag.persistentModelID)
        let rebuilt = try #require(MergeRelationship.identifier(forKey: tagKey, useKnown: false))
        var descriptor = FetchDescriptor<Tag>(predicate: #Predicate { $0.persistentModelID == rebuilt })
        descriptor.fetchLimit = 1
        let found = try ModelContext(fixture.container).fetch(descriptor).first
        #expect(found?.name == tag.name)
    }

    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func theStoreReportsTheValuesAnotherContextsSaveReplaces() throws {
        let fixture = try Fixture()
        let coordinator = try MergeCoordinator(container: fixture.container, types: [Note.self])
        try fixture.theirEdit {
            $0.title = "Theirs"
            $0.likes = 5
            $0.steps.append("serve")
            $0.photo = Data([9])
            $0.tags.append(Tag("c"))
            $0.folder = Folder("Work")
        }
        let records = coordinator.capture.records(forObject: MergeRelationship.key(fixture.id))
        print("Spike: merge policy =", coordinator.capture.mergePolicy ?? "none")
        let record = try #require(records.first)
        for (key, value) in record.base.sorted(by: { $0.key < $1.key }) {
            print("Spike: before", key, "=", type(of: value), value)
        }
        for (key, value) in record.new.sorted(by: { $0.key < $1.key }) {
            print("Spike: after", key, "=", type(of: value), value)
        }
        #expect(records.count == 1)
        #expect(record.author == "sync")
        #expect(record.isComplete)
        #expect(record.base["title"] as? String == "Draft")
        #expect(record.base["likes"] as? Int == 0)
        #expect(record.new["likes"] as? Int == 5)
    }

    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func theReportedValuesRebuildTheSnapshotBeforeTheSave() throws {
        let fixture = try Fixture()
        let coordinator = try MergeCoordinator(container: fixture.container, types: [Note.self])
        let original = fixture.note.mergeSnapshot
        try fixture.theirEdit {
            $0.title = "Theirs"
            $0.body = "a new body"
            $0.likes = 5
            $0.steps.append("serve")
            $0.color = "blue"
            $0.photo = Data([9])
            $0.tags.append(Tag("c"))
            $0.folder = Folder("Work")
        }
        let theirs = try fixture.note(in: ModelContext(fixture.container)).mergeSnapshot
        let record = try #require(coordinator.capture.records(forObject: MergeRelationship.key(fixture.id)).first)
        let rebuilt = SnapshotPatch.apply(record.base, to: theirs, fallback: nil)
        #expect(rebuilt.title == original.title)
        #expect(rebuilt.body == original.body)
        #expect(rebuilt.likes == original.likes)
        #expect(rebuilt.steps == original.steps)
        #expect(rebuilt.color == original.color)
        #expect(rebuilt.photo == original.photo)
        #expect(rebuilt.tags == original.tags)
        #expect(rebuilt.folder == original.folder)
        #expect(SnapshotPatch.matches(record.new, theirs))
    }

    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func theMainContextsOwnSavesAreNotReported() throws {
        let fixture = try Fixture()
        let coordinator = try MergeCoordinator(container: fixture.container, types: [Note.self])
        fixture.note.likes = 4
        try fixture.container.mainContext.save()
        #expect(coordinator.capture.records(forObject: MergeRelationship.key(fixture.id)).isEmpty)
    }

    // MARK: - Merging from the reported base, with no base in the ledger

    /// A coordinator whose ledger has forgotten the note, so only the store's report can give the base.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    func mergeWithoutLedger(ours: (Note) -> Void, theirs: [(Note) -> Void]) throws -> Saved {
        let fixture = try Fixture()
        let coordinator = try MergeCoordinator(container: fixture.container, types: [Note.self])
        coordinator.ledger.setBase(nil, for: fixture.id)
        ours(fixture.note)
        for edit in theirs { try fixture.theirEdit(edit) }
        try coordinator.mergePendingChanges()
        try fixture.container.mainContext.save()
        try coordinator.mergePendingChanges()
        return try fixture.saved()
    }

    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func theReportedBaseSumsCounts() throws {
        let saved = try mergeWithoutLedger(ours: { $0.likes += 1 }, theirs: [{ $0.likes += 2 }])
        #expect(saved.likes == 3)
    }

    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func theReportedBaseMergesWords() throws {
        let saved = try mergeWithoutLedger(ours: { $0.body = "the slow brown fox" }, theirs: [{ $0.body = "the quick brown dog" }])
        #expect(saved.body == "the slow brown dog")
    }

    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func theReportedBaseKeepsAPropertyOnlyTheyChanged() throws {
        let saved = try mergeWithoutLedger(ours: { $0.title = "Mine" }, theirs: [{ $0.color = "blue" }])
        #expect(saved.title == "Mine")
        #expect(saved.color == "blue")
    }

    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func theReportedBaseMergesAnArray() throws {
        let saved = try mergeWithoutLedger(ours: { $0.steps.append("cook") }, theirs: [{ $0.steps.append("serve") }])
        #expect(saved.steps == ["prep", "cook", "serve"])
    }

    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func theReportedBaseMergesToManyRelationships() throws {
        let saved = try mergeWithoutLedger(ours: { $0.tags.append(Tag("mine")) }, theirs: [{ $0.tags.removeAll { $0.name == "a" } }])
        #expect(saved.tags == ["b", "mine"])
    }

    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func twoSavesBeforeAMergeUseTheEarlierBase() throws {
        let saved = try mergeWithoutLedger(ours: { $0.likes += 1 }, theirs: [{ $0.likes += 2 }, { $0.likes += 3 }])
        #expect(saved.likes == 6)
    }

    // MARK: - Imports from a sync service, simulated

    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func anImportMergesWithThisDevicesSavedEdits() throws {
        let fixture = try Fixture()
        let coordinator = try MergeCoordinator(container: fixture.container, types: [Note.self])
        fixture.note.title = "Local"
        fixture.note.likes += 1
        try fixture.container.mainContext.save()
        try coordinator.mergePendingChanges()

        // The other device started from the original note, and its record carries every property.
        try fixture.importRecord {
            $0.title = "Draft"
            $0.likes = 2
            $0.body = "the quick brown dog"
        }
        try coordinator.mergePendingChanges()

        let saved = try fixture.saved()
        #expect(saved.title == "Local")
        #expect(saved.likes == 3)
        #expect(saved.body == "the quick brown dog")
        #expect(!fixture.note.hasChanges)
    }

    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func withoutMergingAnImportRevertsThisDevicesSave() throws {
        let fixture = try Fixture()
        fixture.note.title = "Local"
        try fixture.container.mainContext.save()
        try fixture.importRecord { $0.title = "Draft"; $0.likes = 2 }
        #expect(try fixture.saved().title == "Draft")
    }

    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func anImportMergesUnderUnsavedEdits() throws {
        let fixture = try Fixture()
        let coordinator = try MergeCoordinator(container: fixture.container, types: [Note.self])
        fixture.note.likes += 1
        try fixture.container.mainContext.save()
        try coordinator.mergePendingChanges()
        fixture.note.body = "the slow brown fox"

        try fixture.importRecord { $0.likes = 2; $0.body = "the quick brown dog" }
        try coordinator.mergePendingChanges()
        #expect(fixture.note.likes == 3)
        #expect(fixture.note.body == "the slow brown dog")

        try fixture.container.mainContext.save()
        try coordinator.mergePendingChanges()
        let saved = try fixture.saved()
        #expect(saved.likes == 3)
        #expect(saved.body == "the slow brown dog")
    }

    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func aFinishedExportMakesWhatItSentTheAgreedBase() throws {
        let fixture = try Fixture()
        let coordinator = try MergeCoordinator(container: fixture.container, types: [Note.self])
        fixture.note.likes += 1
        try fixture.container.mainContext.save()
        coordinator.syncEventOccurred(MergeSyncEvent(kind: .export, startDate: .now, endDate: .now, succeeded: true))

        // The other device had our like, and added two of its own.
        try fixture.importRecord { $0.likes = 3 }
        try coordinator.mergePendingChanges()
        #expect(try fixture.saved().likes == 3)
    }

    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func anExportThatStartedBeforeASaveDidntSendIt() throws {
        let fixture = try Fixture()
        let coordinator = try MergeCoordinator(container: fixture.container, types: [Note.self])
        let earlier = Date.now.addingTimeInterval(-60)
        fixture.note.likes += 1
        try fixture.container.mainContext.save()
        coordinator.syncEventOccurred(MergeSyncEvent(kind: .export, startDate: earlier, endDate: .now, succeeded: true))

        // The other device never saw our like.
        try fixture.importRecord { $0.likes = 2 }
        try coordinator.mergePendingChanges()
        #expect(try fixture.saved().likes == 3)
    }

    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func aFailedExportLeavesTheAgreedBase() throws {
        let fixture = try Fixture()
        let coordinator = try MergeCoordinator(container: fixture.container, types: [Note.self])
        fixture.note.likes += 1
        try fixture.container.mainContext.save()
        coordinator.syncEventOccurred(MergeSyncEvent(kind: .export, startDate: .now, endDate: .now, succeeded: false))
        try fixture.importRecord { $0.likes = 2 }
        try coordinator.mergePendingChanges()
        #expect(try fixture.saved().likes == 3)
    }

    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func aFinishedImportEventMerges() throws {
        let fixture = try Fixture()
        let coordinator = try MergeCoordinator(container: fixture.container, types: [Note.self])
        fixture.note.title = "Local"
        try fixture.container.mainContext.save()
        try fixture.importRecord { $0.title = "Draft"; $0.likes = 2 }
        coordinator.syncEventOccurred(MergeSyncEvent(kind: .import, startDate: .now, endDate: .now, succeeded: true))
        let saved = try fixture.saved()
        #expect(saved.title == "Local")
        #expect(saved.likes == 2)
    }

    // MARK: - When a strategy can't settle a clash

    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    func importClash(policy: MergeConflictPolicy) throws -> Saved {
        let fixture = try Fixture()
        let coordinator = try MergeCoordinator(container: fixture.container, types: [Note.self], conflictPolicy: policy)
        fixture.note.color = "green"
        try fixture.container.mainContext.save()
        try coordinator.mergePendingChanges()
        try fixture.importRecord { $0.color = "blue" }
        try coordinator.mergePendingChanges()
        return try fixture.saved()
    }

    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func byDefaultAnImportClashKeepsWhatTheImportWrote() throws {
        #expect(try importClash(policy: .storeDefault).color == "blue")
    }

    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func anImportClashCanKeepThisDevicesSave() throws {
        #expect(try importClash(policy: .keepOurs).color == "green")
    }

    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func byDefaultALocalClashKeepsTheMainContextsEdit() throws {
        let fixture = try Fixture()
        let coordinator = try MergeCoordinator(container: fixture.container, types: [Note.self])
        fixture.note.color = "green"
        try fixture.theirEdit { $0.color = "blue" }
        try coordinator.mergePendingChanges()
        try fixture.container.mainContext.save()
        #expect(try fixture.saved().color == "green")
    }
}
#endif
