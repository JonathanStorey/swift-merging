#if canImport(SwiftData)
import Foundation
import Merging
import MergingSwiftData
import SwiftData
import Testing

@Model @MergeableModel
final class Note {
    @Merge(.keep(.theirs)) var title: String
    @Merge(.byWord) var body: String
    @Merge(.sum) var likes: Int
    var steps: [String]
    var color = "red"
    @Merge(.keep(.theirs)) @Attribute(.externalStorage) var photo: Data?

    init(title: String = "Draft", body: String = "the quick brown fox", likes: Int = 0, steps: [String] = ["prep"]) {
        self.title = title
        self.body = body
        self.likes = likes
        self.steps = steps
    }
}

/// A note's values, read while its context is alive.
struct Saved: Equatable {
    var title: String
    var body: String
    var likes: Int
    var steps: [String]
    var color: String
    var photo: Data?
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
        return Saved(title: note.title, body: note.body, likes: note.likes, steps: note.steps, color: note.color, photo: note.photo)
    }

    /// Changes the note in another context and saves it.
    func theirEdit(_ edit: (Note) -> Void) throws {
        let context = otherContext()
        edit(try note(in: context))
        try context.save()
    }
}

#endif
