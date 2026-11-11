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
    @Relationship(inverse: \Tag.notes) var tags: [Tag] = []
    @Relationship var folder: Folder?

    init(title: String = "Draft", body: String = "the quick brown fox", likes: Int = 0, steps: [String] = ["prep"]) {
        self.title = title
        self.body = body
        self.likes = likes
        self.steps = steps
    }
}

@Model final class Tag {
    var name: String
    var notes: [Note] = []

    init(_ name: String) { self.name = name }
}

@Model final class Folder {
    var name: String

    init(_ name: String) { self.name = name }
}

/// A note's values, read while its context is alive.
struct Saved: Equatable {
    var title: String
    var body: String
    var likes: Int
    var steps: [String]
    var color: String
    var photo: Data?
    var tags: Set<String>
    var folder: String?
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
        note.tags = [Tag("a"), Tag("b")]
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
        return Saved(title: note.title, body: note.body, likes: note.likes, steps: note.steps, color: note.color, photo: note.photo,
                     tags: Set(note.tags.map(\.name)), folder: note.folder?.name)
    }

    /// Changes the note in another context and saves it.
    func theirEdit(author: String = "sync", _ edit: (Note) -> Void) throws {
        let context = otherContext(author: author)
        edit(try note(in: context))
        try context.save()
    }

    /// Saves another device's version of the note as CloudKit's import would: every property, as that
    /// device holds it, written over this one's.
    func importRecord(_ edit: (Note) -> Void) throws {
        try theirEdit(author: MergeCoordinator.cloudKitImportAuthor, edit)
    }
}

#endif
