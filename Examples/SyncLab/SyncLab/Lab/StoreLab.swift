import Foundation
import MergingSwiftData
import SwiftData

/// One local store, no CloudKit. The main context edits without saving while background contexts edit and
/// save, then the main context saves, and its save has to merge first.
@MainActor
enum StoreLab {
    static func run(_ kind: DataKind, editors: Int, _ lab: LabContext) async throws -> [String] {
        let directory = FileManager.default.temporaryDirectory.appending(path: "SyncLab-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let configuration = ModelConfiguration("Local", schema: LabSchema.schema, url: directory.appending(path: "Local.store"),
                                               cloudKitDatabase: .none)
        let container = try ModelContainer(for: LabSchema.schema, configurations: configuration)
        let main = container.mainContext
        main.autosaveEnabled = false

        let key = UUID().uuidString
        let item = Item(key: key)
        main.insert(item)
        Scenario.seed(item, in: main)
        try main.save()
        lab.log("Saved the base item")

        let coordinator = try MergeCoordinator(container: container, types: [Item.self])
        coordinator.startObserving()
        defer { coordinator.stopObserving() }

        kind.edit(item, by: 0, in: main)
        lab.board.set(0, .editing)
        lab.log("Main context \(kind.editSummary(0)), and doesn't save yet")
        try await pause()

        for editor in 1..<editors {
            let context = ModelContext(container)
            context.author = "background-\(editor)"
            context.autosaveEnabled = false
            guard let theirs = try Scenario.item(key, in: context) else { throw LabError("Background \(editor) can't find the item") }
            lab.board.set(editor, .editing)
            kind.edit(theirs, by: editor, in: context)
            try await pause()
            lab.board.set(editor, .sending)
            lab.board.hub = .receiving
            try context.save()
            lab.log("Background \(editor) \(kind.editSummary(editor)), and saves")
            try await pause()
            lab.board.set(editor, .done)
            lab.board.hub = .idle
        }

        lab.board.set(0, .sending)
        lab.board.hub = .merging
        try main.save()
        lab.log("Main context saves, merging the others' saves into its edit first")
        try await pause()
        // Merges that other saves scheduled run now, and anything they change in the main context is saved.
        try coordinator.mergePendingChanges()
        if main.hasChanges { try main.save() }

        guard let stored = try Scenario.storedValues(key, in: container) else { throw LabError("The item is gone from the store") }
        lab.log("Stored: \(stored.summary)")
        let mainValues = ItemValues(item)
        var failures = kind.mismatches(stored, editors: editors)
        if mainValues != stored {
            failures.append("The main context shows \(mainValues.summary), not what's stored")
        }
        return failures
    }

    /// A moment for the diagram to show each step.
    private static func pause() async throws {
        try await Task.sleep(for: .milliseconds(250))
    }
}
