import CoreData
import Foundation
import MergingSwiftData
import Observation
import SwiftData

/// One simulated device: its own store file, CloudKit mirror, merge coordinator, and ledger, on the shared
/// CloudKit container and zone.
@MainActor @Observable
final class Device: Identifiable {
    nonisolated static let names = ["A", "B", "C"]

    enum Connection: Equatable {
        case closed, offline, online
    }

    let name: String
    nonisolated var id: String { name }
    private(set) var connection = Connection.closed
    /// The store's identifier, which CloudKit's events name.
    private(set) var storeIdentifier: String?

    @ObservationIgnored let directory: URL
    @ObservationIgnored private(set) var container: ModelContainer?
    @ObservationIgnored private var coordinator: MergeCoordinator?

    var storeURL: URL { directory.appending(path: "Device\(name).store") }
    var ledgerURL: URL { directory.appending(path: "ledger.json") }

    init(name: String, root: URL) {
        self.name = name
        directory = root.appending(path: "Device\(name)", directoryHint: .isDirectory)
    }

    /// Opens the store, syncing with `cloudKitContainer` when online. Offline, it's the same file with no
    /// mirror, so its saves wait in the history until it's online again.
    func open(online: Bool, cloudKitContainer: String) throws {
        close()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let configuration = ModelConfiguration("Device\(name)", schema: LabSchema.schema, url: storeURL,
                                               cloudKitDatabase: online ? .private(cloudKitContainer) : .none)
        let container = try ModelContainer(for: LabSchema.schema, configurations: configuration)
        container.mainContext.autosaveEnabled = false
        let coordinator = try MergeCoordinator(container: container, types: [Item.self], ledger: FileMergeLedger(url: ledgerURL))
        coordinator.startObserving()
        self.container = container
        self.coordinator = coordinator
        let metadata = try? NSPersistentStoreCoordinator.metadataForPersistentStore(type: .sqlite, at: storeURL)
        storeIdentifier = metadata?[NSStoreUUIDKey] as? String
        connection = online ? .online : .offline
    }

    /// Closes the store. The old mirror gets a moment to wind down before anything reopens the file.
    func close() {
        coordinator?.stopObserving()
        coordinator = nil
        container = nil
        connection = .closed
    }

    func reopen(online: Bool, cloudKitContainer: String) async throws {
        close()
        try await Task.sleep(for: .seconds(1))
        try open(online: online, cloudKitContainer: cloudKitContainer)
    }

    func mainContext() throws -> ModelContext {
        guard let container else { throw LabError("Device \(name) is closed") }
        return container.mainContext
    }

    /// The item as this device's store holds it now.
    func storedValues(_ key: String) throws -> ItemValues? {
        guard let container else { throw LabError("Device \(name) is closed") }
        return try Scenario.storedValues(key, in: container)
    }

    /// Makes editor `editor`'s change in the main context, without saving.
    func edit(_ key: String, _ kind: DataKind, by editor: Int) throws {
        let main = try mainContext()
        guard let item = try Scenario.item(key, in: main) else { throw LabError("Device \(name) doesn't have the item") }
        kind.edit(item, by: editor, in: main)
    }

    func save() throws {
        try mainContext().save()
    }

    /// Deletes the store, its blobs, and its ledger.
    func erase() {
        close()
        try? FileManager.default.removeItem(at: directory)
    }
}
