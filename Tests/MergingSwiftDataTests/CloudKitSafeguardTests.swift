#if canImport(SwiftData)
import CloudKit
import CoreData
import Foundation
@testable import MergingSwiftData
import SwiftData
import Testing

/// What a sync service holds, as a test sets it.
final class FakeRemote: RemoteRecordSource, @unchecked Sendable {
    private let lock = NSLock()
    private let stored: [String: Any]
    private var _calls: [[String]] = []

    init(_ stored: [String: Any]) { self.stored = stored }

    /// The properties asked for, one list per fetch.
    var calls: [[String]] { lock.synchronized { _calls } }

    func values(forObject object: String, keys: [String]) async throws -> RemoteValues? {
        lock.synchronized { _calls.append(keys) }
        return RemoteValues(values: stored.filter { keys.contains($0.key) })
    }
}

@MainActor
@Suite struct CloudKitSafeguardTests {
    // MARK: - Canaries: a failure here means CloudKit's internals moved and a safeguard needs another look

    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func cloudKitsMirroringClassesAreStillThere() {
        for name in ["NSCloudKitMirroringDelegate", "PFCloudKitImportRecordsWorkItem", "PFCloudKitSerializer", "NSCKRecordMetadata"] {
            let found = NSClassFromString(name) != nil
            print("Canary: class", name, found ? "found" : "MISSING")
            #expect(found, "\(name) is gone")
        }
    }

    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func theImporterStillAppliesRecordsAttributeByAttribute() {
        // Whichever of Core Data's CloudKit classes holds it in this release.
        _ = NSClassFromString("PFCloudKitSerializer")
        var found: [String] = []
        var count: UInt32 = 0
        if let classes = objc_copyClassList(&count) {
            defer { free(UnsafeMutableRawPointer(classes)) }
            for index in 0..<Int(count) {
                let owner: AnyClass = classes[index]
                let name = NSStringFromClass(owner)
                guard name.hasPrefix("PFCloudKit") || name.hasPrefix("NSCloudKit") else { continue }
                for (target, mark) in [(owner, "-"), (object_getClass(owner), "+")] {
                    guard let target else { continue }
                    var methodCount: UInt32 = 0
                    guard let methods = class_copyMethodList(target, &methodCount) else { continue }
                    defer { free(methods) }
                    for item in 0..<Int(methodCount) {
                        let selector = NSStringFromSelector(method_getName(methods[item]))
                        if selector.hasPrefix("applyUpdatedRecords") { found.append("\(mark)[\(name) \(selector)]") }
                    }
                }
            }
        }
        print("Canary: importer apply methods =", found.isEmpty ? "MISSING" : found.joined(separator: ", "))
        #expect(!found.isEmpty)
    }

    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func cloudKitsPerObjectMetadataStillHasItsFields() throws {
        let metadata: AnyClass = try #require(NSClassFromString(StoreChangeCapture.metadataEntity))
        for name in ["needsUpload", "entityPK", "ckRecordSystemFields"] {
            let found = class_getProperty(metadata, name) != nil || class_getInstanceMethod(metadata, NSSelectorFromString(name)) != nil
            print("Canary: NSCKRecordMetadata.\(name)", found ? "found" : "MISSING")
            #expect(found, "\(name) is gone")
        }
    }

    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func cloudKitStillNamesItsContextsAsWeDo() throws {
        print("Canary: import context name exported =", CloudKitNames.exported("NSCloudKitMirroringDelegateImportContextName") ?? "no")
        // CloudKit's own check for its contexts' names, which its history analyzer uses to skip their saves.
        let analyzer: AnyClass = try #require(NSClassFromString("PFCloudKitHistoryAnalyzer"))
        let selector = NSSelectorFromString("isPrivateContextName:")
        let method = try #require(class_getClassMethod(analyzer, selector))
        typealias Check = @convention(c) (AnyClass, Selector, NSString) -> Bool
        let isPrivate = unsafeBitCast(method_getImplementation(method), to: Check.self)
        for name in [CloudKitNames.importAuthor, CloudKitNames.exportAuthor] {
            let known = isPrivate(analyzer, selector, name as NSString)
            print("Canary: CloudKit recognizes context name", name, known ? "yes" : "NO")
            #expect(known, "CloudKit no longer calls a context \(name)")
        }
        #expect(!isPrivate(analyzer, selector, MergeCoordinator.localAuthor as NSString))
        #expect(MergeCoordinator.cloudKitImportAuthor == CloudKitNames.importAuthor)
    }

    // MARK: - CloudKit's own saves, simulated with a store of its metadata rows

    /// A store with CloudKit's metadata entity, as the capture sees it.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @MainActor
    struct MetadataStore {
        let context: NSManagedObjectContext
        let entity: NSEntityDescription
        let storeIdentifier: String
        let capture: StoreChangeCapture

        init() throws {
            let entity = NSEntityDescription()
            entity.name = StoreChangeCapture.metadataEntity
            let needsUpload = NSAttributeDescription()
            needsUpload.name = "needsUpload"
            needsUpload.type = .boolean
            let entityPK = NSAttributeDescription()
            entityPK.name = "entityPK"
            entityPK.type = .integer64
            let fields = NSAttributeDescription()
            fields.name = "ckRecordSystemFields"
            fields.type = .binaryData
            fields.isOptional = true
            entity.properties = [needsUpload, entityPK, fields]
            let model = NSManagedObjectModel()
            model.entities = [entity]
            let url = FileManager.default.temporaryDirectory.appending(path: "metadata-\(UUID().uuidString).store")
            let coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
            let store = try coordinator.addPersistentStore(type: .sqlite, at: url)
            context = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
            context.persistentStoreCoordinator = coordinator
            self.entity = entity
            storeIdentifier = try #require(store.identifier)
            capture = StoreChangeCapture(storeURL: url, ignoredAuthors: [MergeCoordinator.localAuthor],
                                         importAuthors: [MergeCoordinator.cloudKitImportAuthor])
            capture.start()
        }

        /// A note's record's system fields, as CloudKit keeps them.
        static func systemFields(recordName: String) -> Data {
            let record = CKRecord(recordType: "CD_Note", recordID: CKRecord.ID(recordName: recordName,
                                                                              zoneID: CKRecordZone.ID(zoneName: "com.apple.coredata.cloudkit.zone")))
            let coder = NSKeyedArchiver(requiringSecureCoding: true)
            record.encodeSystemFields(with: coder)
            coder.finishEncoding()
            return coder.encodedData
        }

        /// A row for the note with this primary key, as CloudKit inserts it before the first export.
        func insertRow(primaryKey: Int64, recordName: String?) throws -> NSManagedObject {
            let row = NSManagedObject(entity: entity, insertInto: context)
            row.setValue(true, forKey: "needsUpload")
            row.setValue(primaryKey, forKey: "entityPK")
            row.setValue(recordName.map { Self.systemFields(recordName: $0) }, forKey: "ckRecordSystemFields")
            context.transactionAuthor = "NSCloudKitMirroringDelegate.setup"
            try context.save()
            return row
        }
    }

    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func aFinishedExportConfirmsTheObjectItSent() throws {
        let store = try MetadataStore()
        let row = try store.insertRow(primaryKey: 7, recordName: "note-7")
        let inserted = store.capture.takeSyncNotes()
        #expect(inserted.allSatisfy { !$0.exported && !$0.imported })

        store.context.transactionAuthor = CloudKitNames.exportAuthor
        row.setValue(false, forKey: "needsUpload")
        try store.context.save()

        let notes = store.capture.takeSyncNotes()
        let note = try #require(notes.first)
        print("Spike: export confirmation for", note.object)
        #expect(notes.count == 1)
        #expect(note.exported)
        #expect(!note.imported)
        #expect(note.object == "x-coredata://\(store.storeIdentifier)/Note/p7")
        #expect(note.recordID?.recordName == "note-7")
        #expect(store.capture.recordID(forObject: note.object)?.recordName == "note-7")
    }

    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func anImportNotesTheObjectWhoseRecordChanged() throws {
        let store = try MetadataStore()
        let row = try store.insertRow(primaryKey: 3, recordName: nil)
        #expect(store.capture.takeSyncNotes().isEmpty)

        store.context.transactionAuthor = MergeCoordinator.cloudKitImportAuthor
        // An import brings the record's new system fields.
        row.setValue(MetadataStore.systemFields(recordName: "note-3"), forKey: "ckRecordSystemFields")
        try store.context.save()

        let note = try #require(store.capture.takeSyncNotes().first)
        #expect(note.imported)
        #expect(!note.exported)
        #expect(note.object == "x-coredata://\(store.storeIdentifier)/Note/p3")
    }

    // MARK: - Export confirmations in a merge

    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func aConfirmedExportMakesWhatItSentTheAgreedBase() throws {
        let fixture = try Fixture()
        let coordinator = try MergeCoordinator(container: fixture.container, types: [Note.self])
        fixture.note.likes += 1
        try fixture.container.mainContext.save()
        try coordinator.mergePendingChanges()
        coordinator.capture.noteSync(object: MergeRelationship.key(fixture.id), recordID: nil, exported: true, imported: false)
        try coordinator.mergePendingChanges()

        // The other device had our like, and added two of its own.
        try fixture.importRecord { $0.likes = 3 }
        try coordinator.mergePendingChanges()
        #expect(try fixture.saved().likes == 3)
    }

    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func onceExportsAreConfirmedAnUnconfirmedObjectWaits() throws {
        let fixture = try Fixture()
        let coordinator = try MergeCoordinator(container: fixture.container, types: [Note.self])
        let other = MergeRelationship.key(fixture.id) + "999"
        fixture.note.likes += 1
        try fixture.container.mainContext.save()
        coordinator.capture.noteSync(object: other, recordID: nil, exported: true, imported: false)
        try coordinator.mergePendingChanges()
        // The export finished, but didn't confirm the note, so it didn't send it.
        coordinator.syncEventOccurred(MergeSyncEvent(kind: .export, startDate: .now, endDate: .now, succeeded: true))

        try fixture.importRecord { $0.likes = 2 }
        try coordinator.mergePendingChanges()
        #expect(try fixture.saved().likes == 3)
    }

    // MARK: - Fetching what CloudKit's importer kept back

    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func theMacroListsTheAttributesThatMergeByAStrategy() {
        #expect(Note.mergeStrategyProperties == ["title", "body", "likes", "steps", "photo"])
    }

    /// A note this device liked once and saved, with a sync service that holds `remote`.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    func likedOnce(remote: [String: Any]) throws -> (Fixture, MergeCoordinator, FakeRemote) {
        let fixture = try Fixture()
        let coordinator = try MergeCoordinator(container: fixture.container, types: [Note.self])
        let source = FakeRemote(remote)
        coordinator.remoteSource = source
        fixture.note.likes += 1
        try fixture.container.mainContext.save()
        try coordinator.mergePendingChanges()
        return (fixture, coordinator, source)
    }

    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func aValueTheImporterKeptBackIsFetchedAndMerged() async throws {
        let (fixture, coordinator, remote) = try likedOnce(remote: ["likes": 2])
        // The other device liked it twice and changed the body. CloudKit kept our likes, since we hadn't
        // exported them, and took the body.
        try fixture.importRecord { $0.body = "the quick brown dog" }
        try coordinator.mergePendingChanges()
        await coordinator.finishRemoteFetches()

        #expect(remote.calls == [["likes"]])
        let saved = try fixture.saved()
        #expect(saved.likes == 3)
        #expect(saved.body == "the quick brown dog")
    }

    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func anImportThatOnlyTouchedAKeptBackValueStillFetches() async throws {
        let (fixture, coordinator, remote) = try likedOnce(remote: ["likes": 2])
        // CloudKit kept our likes, so the note's own row didn't change: only its sync metadata did.
        coordinator.capture.noteSync(object: MergeRelationship.key(fixture.id), recordID: nil, exported: false, imported: true)
        try coordinator.mergePendingChanges()
        await coordinator.finishRemoteFetches()

        #expect(remote.calls == [["likes"]])
        #expect(try fixture.saved().likes == 3)
    }

    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func aFetchedValueMergesUnderUnsavedEdits() async throws {
        let (fixture, coordinator, _) = try likedOnce(remote: ["likes": 2])
        fixture.note.likes += 1
        try fixture.importRecord { $0.body = "the quick brown dog" }
        try coordinator.mergePendingChanges()
        await coordinator.finishRemoteFetches()
        #expect(fixture.note.likes == 4)

        try fixture.container.mainContext.save()
        try coordinator.mergePendingChanges()
        #expect(try fixture.saved().likes == 4)
    }

    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func aServiceThatAlreadyHasThisDevicesValueChangesNothing() async throws {
        let (fixture, coordinator, remote) = try likedOnce(remote: ["likes": 1])
        try fixture.importRecord { $0.body = "the quick brown dog" }
        try coordinator.mergePendingChanges()
        await coordinator.finishRemoteFetches()
        #expect(remote.calls == [["likes"]])
        #expect(try fixture.saved().likes == 1)

        // That made our like agreed, so the other device's next two count once each.
        try fixture.importRecord { $0.likes = 3 }
        try coordinator.mergePendingChanges()
        await coordinator.finishRemoteFetches()
        #expect(try fixture.saved().likes == 3)
    }

    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func anImportThatBroughtTheValueNeedsNoFetch() async throws {
        let (fixture, coordinator, remote) = try likedOnce(remote: ["likes": 99])
        try fixture.importRecord { $0.likes = 2 }
        try coordinator.mergePendingChanges()
        await coordinator.finishRemoteFetches()
        #expect(remote.calls.isEmpty)
        #expect(try fixture.saved().likes == 3)
    }

    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func withNoUnexportedEditThereIsNothingToFetch() async throws {
        let fixture = try Fixture()
        let coordinator = try MergeCoordinator(container: fixture.container, types: [Note.self])
        let remote = FakeRemote(["likes": 99])
        coordinator.remoteSource = remote
        try fixture.importRecord { $0.body = "the quick brown dog" }
        coordinator.capture.noteSync(object: MergeRelationship.key(fixture.id), recordID: nil, exported: false, imported: true)
        try coordinator.mergePendingChanges()
        await coordinator.finishRemoteFetches()
        #expect(remote.calls.isEmpty)
        #expect(try fixture.saved().body == "the quick brown dog")
    }

    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func withoutAKnownRecordCloudKitIsNeverAsked() async throws {
        let fixture = try Fixture()
        let coordinator = try MergeCoordinator(container: fixture.container, types: [Note.self])
        let values = try await coordinator.remoteSource?.values(forObject: MergeRelationship.key(fixture.id), keys: ["likes"])
        #expect(values == nil)
    }
}
#endif
