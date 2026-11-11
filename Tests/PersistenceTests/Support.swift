#if canImport(SwiftData)
import CloudKit
import CoreData
import Foundation
@testable import Persistence
import SwiftData
import Testing

@Model final class Item {
    var name: String
    var tags: [String]

    init(_ name: String, tags: [String] = []) {
        self.name = name
        self.tags = tags
    }
}

/// A fresh `UserDefaults` suite name, so tests don't share saved state.
func freshSuite() -> String {
    let name = "PersistenceTests.\(UUID().uuidString)"
    UserDefaults(suiteName: name)?.removePersistentDomain(forName: name)
    return name
}

/// A SwiftData container on a fresh file, with its store's identifier.
struct ModelFixture {
    let container: ModelContainer
    let store: String

    init() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "PersistenceTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let configuration = ModelConfiguration(url: directory.appending(path: "store.sqlite"), cloudKitDatabase: .none)
        container = try ModelContainer(for: Item.self, configurations: configuration)
        // The store file exists once the container has loaded it.
        _ = try ModelContext(container).fetchCount(FetchDescriptor<Item>())
        store = try #require(StoreRecords.storeIdentifier(at: configuration.url))
    }
}

/// A Core Data stack with an `Item` entity and a stand-in for CloudKit's `NSCKRecordMetadata`, so a test
/// can save rows the way CloudKit's mirroring does.
final class MirrorFixture {
    let container: NSPersistentContainer
    var store: String { container.persistentStoreCoordinator.persistentStores[0].identifier }

    init() throws {
        let item = NSEntityDescription()
        item.name = "Item"
        let name = NSAttributeDescription()
        name.name = "name"
        name.type = .string
        name.isOptional = true
        item.properties = [name]

        let metadata = NSEntityDescription()
        metadata.name = StoreRecords.metadataEntity
        let needsUpload = NSAttributeDescription()
        needsUpload.name = "needsUpload"
        needsUpload.type = .boolean
        needsUpload.isOptional = true
        let entityPK = NSAttributeDescription()
        entityPK.name = "entityPK"
        entityPK.type = .integer64
        entityPK.isOptional = true
        let fields = NSAttributeDescription()
        fields.name = "ckRecordSystemFields"
        fields.type = .binaryData
        fields.isOptional = true
        metadata.properties = [needsUpload, entityPK, fields]

        let model = NSManagedObjectModel()
        model.entities = [item, metadata]
        container = NSPersistentContainer(name: "Mirror-\(UUID().uuidString)", managedObjectModel: model)
        let url = FileManager.default.temporaryDirectory.appending(path: "Mirror-\(UUID().uuidString).sqlite")
        container.persistentStoreDescriptions = [NSPersistentStoreDescription(url: url)]
        var loadError: (any Error)?
        container.loadPersistentStores { _, error in loadError = error }
        if let loadError { throw loadError }
    }

    /// Saves a new item, as the app would, and returns it.
    func saveItem(author: String? = nil) throws -> NSManagedObject {
        let context = container.newBackgroundContext()
        context.transactionAuthor = author
        return try context.performAndWait {
            let object = NSEntityDescription.insertNewObject(forEntityName: "Item", into: context)
            object.setValue("first", forKey: "name")
            try context.save()
            return object
        }
    }

    /// Saves the item's metadata row the way CloudKit does, by `author`.
    @discardableResult
    func saveRow(for object: NSManagedObject, needsUpload: Bool, row existing: NSManagedObject? = nil,
                 author: String = "NSCloudKitMirroringDelegate.export") throws -> NSManagedObject {
        let context = container.newBackgroundContext()
        context.transactionAuthor = author
        var row: NSManagedObject!
        var saveError: (any Error)?
        context.performAndWait {
            if let existing {
                row = context.object(with: existing.objectID)
            } else {
                row = NSEntityDescription.insertNewObject(forEntityName: StoreRecords.metadataEntity, into: context)
                let key = object.objectID.uriRepresentation().lastPathComponent  // "p<primary key>"
                row.setValue(Int64(key.dropFirst())!, forKey: "entityPK")
                let record = CKRecord(recordType: "CD_Item", recordID: CKRecord.ID(recordName: UUID().uuidString))
                let coder = NSKeyedArchiver(requiringSecureCoding: true)
                record.encodeSystemFields(with: coder)
                coder.finishEncoding()
                row.setValue(coder.encodedData, forKey: "ckRecordSystemFields")
            }
            row.setValue(needsUpload, forKey: "needsUpload")
            do { try context.save() } catch { saveError = error }
        }
        if let saveError { throw saveError }
        return row
    }
}
#endif
