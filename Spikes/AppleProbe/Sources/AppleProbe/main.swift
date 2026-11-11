import CloudKit
import CoreData
import Foundation
import SwiftData

// Probes what SwiftData exposes underneath: the Core Data objects it wraps, the notifications a save
// posts, whether committedValues gives a base, and whether CloudKit events fire under SwiftData.

@Model final class Item {
    var name: String = ""
    var count: Int = 0
    init() {}
}

func section(_ title: String) { print("\n==== \(title) ====") }

var seen = Set<ObjectIdentifier>()
var found: [String: [AnyObject]] = [:]

/// Walks a value's stored properties, printing labels and types, and collects any Core Data objects.
func walk(_ value: Any, label: String, depth: Int, maxDepth: Int = 5) {
    let indent = String(repeating: "  ", count: depth)
    let mirror = Mirror(reflecting: value)
    print("\(indent)\(label): \(type(of: value)) [\(mirror.displayStyle.map { "\($0)" } ?? "-")]")
    if let object = value as AnyObject?, mirror.displayStyle == .class {
        let id = ObjectIdentifier(object)
        if seen.contains(id) { return }
        seen.insert(id)
    }
    for (name, type) in [("NSManagedObjectContext", NSManagedObjectContext.self as AnyClass),
                         ("NSPersistentContainer", NSPersistentContainer.self),
                         ("NSPersistentCloudKitContainer", NSPersistentCloudKitContainer.self),
                         ("NSPersistentStoreCoordinator", NSPersistentStoreCoordinator.self),
                         ("NSManagedObject", NSManagedObject.self)] {
        if let object = value as AnyObject?, object.isKind(of: type) {
            found[name, default: []].append(object)
            print("\(indent)  ^ FOUND \(name)")
        }
    }
    guard depth < maxDepth else { return }
    for (index, child) in mirror.children.prefix(40).enumerated() {
        walk(child.value, label: child.label ?? "[\(index)]", depth: depth + 1, maxDepth: maxDepth)
    }
}

var notes: [String] = []
let observer = NotificationCenter.default.addObserver(forName: nil, object: nil, queue: nil) { note in
    let name = note.name.rawValue
    if name.hasPrefix("NSWindow") || name.hasPrefix("NSApplication") || name.hasPrefix("_NSThread") { return }
    let keys = (note.userInfo?.keys.map { "\($0)" } ?? []).sorted().joined(separator: ",")
    let line = "NOTE \(name) object=\(type(of: note.object as Any)) keys=[\(keys)]"
    notes.append(line)
    print(line)
    if name == NSPersistentCloudKitContainer.eventChangedNotification.rawValue,
       let event = note.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey] as? NSPersistentCloudKitContainer.Event {
        print("  CLOUDKIT EVENT type=\(event.type.rawValue) succeeded=\(event.succeeded) end=\(String(describing: event.endDate)) error=\(String(describing: event.error))")
    }
    if name == "NSManagedObjectContextObjectsDidChangeNotification" || name == "NSObjectsChangedInManagingContextNotification" {
        for key in [NSUpdatedObjectsKey, NSInsertedObjectsKey, NSRefreshedObjectsKey] {
            if let objects = note.userInfo?[key] as? Set<NSManagedObject> {
                for object in objects {
                    print("  \(key): \(object.entity.name ?? "?") changed=\(object.changedValues()) committed=\(object.committedValues(forKeys: nil))")
                    found["NSManagedObject", default: []].append(object)
                }
            }
        }
    }
}

MainActor.assumeIsolated {
    do {
        section("Versions")
        print(ProcessInfo.processInfo.operatingSystemVersionString)

        let url = FileManager.default.temporaryDirectory.appending(path: "probe-\(UUID().uuidString).store")
        let container = try ModelContainer(for: Item.self, configurations: ModelConfiguration(url: url))
        let main = container.mainContext
        main.autosaveEnabled = false

        section("Insert and save in main")
        let item = Item()
        item.name = "base"
        main.insert(item)
        try main.save()

        section("Mirror: ModelContainer")
        walk(container, label: "container", depth: 0)
        section("Mirror: ModelContext")
        walk(main, label: "mainContext", depth: 0)
        section("Mirror: Item")
        walk(item, label: "item", depth: 0)
        section("Found Core Data objects")
        for (name, objects) in found { print(name, objects.count, objects.map { "\(type(of: $0))" }) }

        section("Edit in main (unsaved), then another context saves")
        item.name = "ours"
        item.count = 1
        let other = ModelContext(container)
        other.author = "sync"
        let theirs = try other.fetch(FetchDescriptor<Item>()).first!
        theirs.name = "theirs"
        theirs.count = 5
        try other.save()
        print("main item after their save: name=\(item.name) count=\(item.count) hasChanges=\(item.hasChanges)")

        section("committedValues on Core Data objects found")
        for object in found["NSManagedObject"] ?? [] {
            if let managed = object as? NSManagedObject {
                print("\(managed.objectID.uriRepresentation()) changed=\(managed.changedValues()) committed=\(managed.committedValues(forKeys: nil))")
            }
        }
        for object in found["NSManagedObjectContext"] ?? [] {
            if let context = object as? NSManagedObjectContext {
                print("MOC: name=\(String(describing: context.name)) author=\(String(describing: context.transactionAuthor)) mergePolicy=\(type(of: context.mergePolicy)) \(context.mergePolicy) automaticallyMerges=\(context.automaticallyMergesChangesFromParent) registered=\(context.registeredObjects.count)")
                for registered in context.registeredObjects {
                    print("  registered \(registered.entity.name ?? "?") changed=\(registered.changedValues()) committed=\(registered.committedValues(forKeys: nil)) snapshotFromStore? hasPersistentChangedValues=\(registered.hasPersistentChangedValues)")
                }
            }
        }

        section("Main saves")
        do { try main.save(); print("main save ok") } catch { print("main save error: \(error)") }
        let check = ModelContext(container)
        let saved = try check.fetch(FetchDescriptor<Item>()).first!
        print("store after main save: name=\(saved.name) count=\(saved.count)")

        section("CloudKit configuration without entitlements")
        let cloudURL = FileManager.default.temporaryDirectory.appending(path: "probe-cloud-\(UUID().uuidString).store")
        do {
            let cloud = try ModelContainer(for: Item.self, configurations: ModelConfiguration(url: cloudURL, cloudKitDatabase: .private("iCloud.com.example.probe")))
            print("cloud container created")
            walk(cloud, label: "cloudContainer", depth: 0, maxDepth: 4)
        } catch {
            print("cloud container error: \(error)")
        }
        RunLoop.main.run(until: Date().addingTimeInterval(5))

        section("Notification names seen")
        for name in Set(notes.map { $0.split(separator: " ")[1] }).sorted() { print(name) }
    } catch {
        print("PROBE ERROR: \(error)")
    }
}
NotificationCenter.default.removeObserver(observer)
