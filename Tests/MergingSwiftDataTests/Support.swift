#if canImport(SwiftData)
import Foundation
import Merging
import MergingSwiftData
import SwiftData
import Testing

@Model final class Note {
    var title: String
    var body: String
    var likes: Int
    var steps: [String]
    var color: String

    init(title: String = "Draft", body: String = "the quick brown fox", likes: Int = 0, steps: [String] = ["prep"], color: String = "red") {
        self.title = title
        self.body = body
        self.likes = likes
        self.steps = steps
        self.color = color
    }
}

// What `@Merge(.strategy)` on Note's own properties will generate. `color` has no strategy, so it keeps
// the side that changed it.
extension Note: MergeableModel {
    struct MergeSnapshot: Codable, Equatable, Mergeable {
        @Merged(.keep(.theirs)) var title = ""
        @Merged(.byWord) var body = ""
        @Merged(.sum) var likes = 0
        var steps: [String] = []
        var color = ""
    }

    var mergeSnapshot: MergeSnapshot {
        var snapshot = MergeSnapshot()
        snapshot.title = title
        snapshot.body = body
        snapshot.likes = likes
        snapshot.steps = steps
        snapshot.color = color
        return snapshot
    }

    func applyMergeSnapshot(_ snapshot: MergeSnapshot) {
        if title != snapshot.title { title = snapshot.title }
        if body != snapshot.body { body = snapshot.body }
        if likes != snapshot.likes { likes = snapshot.likes }
        if steps != snapshot.steps { steps = snapshot.steps }
        if color != snapshot.color { color = snapshot.color }
    }

    static var mergeKeyPaths: [PartialKeyPath<Note>] { [\.title, \.body, \.likes, \.steps, \.color] }
}

/// A note's values, read while its context is alive.
struct Saved: Equatable {
    var title: String
    var body: String
    var likes: Int
    var steps: [String]
    var color: String
}

/// A container on a fresh file, since history needs a store on disk, with one saved note.
@available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
@MainActor
struct Fixture {
    let container: ModelContainer
    let note: Note
    let id: PersistentIdentifier

    init() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "merging-\(UUID().uuidString).store")
        container = try ModelContainer(for: Note.self, configurations: ModelConfiguration(url: url))
        container.mainContext.autosaveEnabled = false
        note = Note()
        container.mainContext.insert(note)
        try container.mainContext.save()
        id = note.persistentModelID
    }

    /// Another context, as a sync engine or a background import would have.
    func otherContext(author: String = "sync") -> ModelContext {
        let context = ModelContext(container)
        context.author = author
        context.autosaveEnabled = false
        return context
    }

    /// The note in `context`.
    func note(in context: ModelContext) throws -> Note {
        let id = id
        var descriptor = FetchDescriptor<Note>(predicate: #Predicate { $0.persistentModelID == id })
        descriptor.fetchLimit = 1
        return try #require(try context.fetch(descriptor).first)
    }

    /// The note as the store holds it.
    func saved() throws -> Saved {
        let context = ModelContext(container)
        let note = try note(in: context)
        return Saved(title: note.title, body: note.body, likes: note.likes, steps: note.steps, color: note.color)
    }

    /// Changes the note in another context and saves it.
    func theirEdit(_ edit: (Note) -> Void) throws {
        let context = otherContext()
        edit(try note(in: context))
        try context.save()
    }
}

#endif
