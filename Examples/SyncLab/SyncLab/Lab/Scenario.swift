import Foundation
import SwiftData

/// The kinds of data the lab syncs, one test each per stage.
enum DataKind: String, CaseIterable, Identifiable, Sendable {
    case string, strings, codable, relationship, blob

    var id: String { rawValue }

    var title: String {
        switch self {
        case .string: "String"
        case .strings: "[String]"
        case .codable: "Codable struct"
        case .relationship: "Relationship"
        case .blob: "External storage blob"
        }
    }

    var symbol: String {
        switch self {
        case .string: "textformat"
        case .strings: "list.bullet"
        case .codable: "curlybraces"
        case .relationship: "link"
        case .blob: "photo.stack"
        }
    }

    var strategy: String {
        switch self {
        case .string: "@Merge(.byWord)"
        case .strings: "@Merge(.byElement)"
        case .codable: "@Merge(.byNode)"
        case .relationship: "@Merge(.byMembership)"
        case .blob: "@Merge(.keep(.theirs)) @Attribute(.externalStorage)"
        }
    }

    /// What editor `editor` (0, 1 or 2) changes.
    func editSummary(_ editor: Int) -> String {
        switch self {
        case .string: "upper-cases “\(Scenario.titleWord(Scenario.stringWords[editor]))” in the title"
        case .strings: "appends “editor-\(editor)” to the steps"
        case .codable: ["sets size.width to 5 and adds a caption", "adds options[\"editor-1\"]", "appends a point"][editor]
        case .relationship: "adds the label “editor-\(editor)”"
        case .blob: editor == 0 ? "replaces the 256 KB blob" : "upper-cases “\(Scenario.titleWord(Scenario.blobTitleWords[editor]))” in the title"
        }
    }

    /// Makes editor `editor`'s change to a model object.
    @MainActor func edit(_ item: Item, by editor: Int, in context: ModelContext) {
        switch self {
        case .string:
            item.title = Scenario.uppercasing(item.title, word: Scenario.stringWords[editor])
        case .strings:
            item.steps = item.steps + ["editor-\(editor)"]
        case .codable:
            var spec = item.spec
            Scenario.edit(&spec, by: editor)
            item.spec = spec
        case .relationship:
            let label = Tag(name: "editor-\(editor)")
            context.insert(label)
            item.labels = (item.labels ?? []) + [label]
        case .blob:
            if editor == 0 {
                item.blob = Scenario.editedBlob
            } else {
                item.title = Scenario.uppercasing(item.title, word: Scenario.blobTitleWords[editor])
            }
        }
    }

    /// Whether `values` hold editor `editor`'s change.
    func reflects(_ values: ItemValues?, editor: Int) -> Bool {
        guard let values else { return false }
        var draft = Draft()
        draft.apply(self, by: editor)
        let edited = draft.values
        switch self {
        case .string: return values.title.split(separator: " ")[Scenario.stringWords[editor]] == edited.title.split(separator: " ")[Scenario.stringWords[editor]]
        case .strings: return values.steps.contains("editor-\(editor)")
        case .codable:
            switch editor {
            case 0: return values.spec.size.width == edited.spec.size.width
            case 1: return values.spec.options["editor-1"] != nil
            default: return values.spec.points.count > Scenario.baseSpec.points.count
            }
        case .relationship: return values.labels.contains("editor-\(editor)")
        case .blob:
            if editor == 0 { return values.blob == edited.blob }
            let word = Scenario.blobTitleWords[editor]
            return values.title.split(separator: " ")[word] == edited.title.split(separator: " ")[word]
        }
    }

    /// What the item should hold once `editors` editors' changes have all merged.
    func expected(editors: Int) -> ItemValues {
        var draft = Draft()
        for editor in 0..<editors { draft.apply(self, by: editor) }
        return draft.values
    }

    /// How `actual` differs from what `editors` editors' changes should merge to, one line per property.
    func mismatches(_ actual: ItemValues, editors: Int) -> [String] {
        let want = expected(editors: editors)
        var lines: [String] = []
        if actual.title != want.title { lines.append("title is “\(actual.title)”, expected “\(want.title)”") }
        // Two devices may order each other's insertions differently, so the steps are compared as a list of
        // members here, and devices are checked against each other separately.
        if actual.steps.sorted() != want.steps.sorted() { lines.append("steps are \(actual.steps), expected \(want.steps)") }
        if actual.spec != want.spec { lines.append("spec is \(actual.spec.text), expected \(want.spec.text)") }
        if actual.labels != want.labels {
            lines.append("labels are \(actual.labels.sorted()), expected \(want.labels.sorted())")
        }
        if actual.blob != want.blob {
            lines.append("blob is \(actual.blob?.description ?? "nil"), expected \(want.blob?.description ?? "nil")")
        }
        return lines
    }
}

/// The values every test starts from, and the edits it makes.
enum Scenario {
    static let baseTitle = "alpha bravo charlie delta echo"
    static let baseSteps = ["one", "two"]
    static let baseSpec = Spec(options: ["base": 0])
    static let baseLabel = "base"
    /// Large enough that SwiftData keeps it in a file beside the store, and CloudKit sends it as an asset.
    static let baseBlob = blob(seed: 0)
    static let editedBlob = blob(seed: 1)

    /// The title words the String test's editors change.
    static let stringWords = [0, 2, 4]
    /// The title words the blob test's other editors change while editor 0 replaces the blob.
    static let blobTitleWords = [0, 1, 3]

    static func blob(seed: Int) -> Data {
        Data((0..<(256 * 1024)).map { UInt8(truncatingIfNeeded: $0 &* 31 &+ seed &* 7 &+ ($0 >> 10)) })
    }

    static func titleWord(_ index: Int) -> String {
        String(baseTitle.split(separator: " ")[index])
    }

    static func uppercasing(_ title: String, word index: Int) -> String {
        var words = title.split(separator: " ").map(String.init)
        guard words.indices.contains(index) else { return title }
        words[index] = words[index].uppercased()
        return words.joined(separator: " ")
    }

    static func edit(_ spec: inout Spec, by editor: Int) {
        switch editor {
        case 0:
            spec.size.width = 5
            spec.caption = "from editor 0"
        case 1:
            spec.options["editor-1"] = 1
        default:
            spec.points.append(Spec.Point(x: 2, y: 2))
        }
    }

    /// Fills a new item with the base values. Insert the item first.
    @MainActor static func seed(_ item: Item, in context: ModelContext) {
        item.title = baseTitle
        item.steps = baseSteps
        item.spec = baseSpec
        item.blob = baseBlob
        let label = Tag(name: baseLabel)
        context.insert(label)
        item.labels = [label]
    }

    /// The item with `key` in `context`.
    @MainActor static func item(_ key: String, in context: ModelContext) throws -> Item? {
        var descriptor = FetchDescriptor<Item>(predicate: #Predicate { $0.key == key })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    /// The item with `key` as the store holds it now, read through a fresh context.
    @MainActor static func storedValues(_ key: String, in container: ModelContainer) throws -> ItemValues? {
        let context = ModelContext(container)
        return try withExtendedLifetime(context) {
            try item(key, in: context).map(ItemValues.init)
        }
    }
}

/// An item's values as plain data, with relationships as names and the blob as its size and hash.
struct ItemValues: Equatable, Sendable {
    var title: String
    var steps: [String]
    var spec: Spec
    var labels: Set<String>
    var blob: BlobSummary?

    init(title: String, steps: [String], spec: Spec, labels: Set<String>, blob: BlobSummary?) {
        self.title = title
        self.steps = steps
        self.spec = spec
        self.labels = labels
        self.blob = blob
    }

    @MainActor init(_ item: Item) {
        title = item.title
        steps = item.steps
        spec = item.spec
        labels = Set((item.labels ?? []).map(\.name))
        blob = item.blob.map(BlobSummary.init)
    }

    var summary: String {
        "title “\(title)”, steps \(steps), spec \(spec.text), labels \(labels.sorted()), blob \(blob?.description ?? "nil")"
    }
}

/// A blob's size and FNV-1a hash, so two blobs compare without holding both.
struct BlobSummary: Equatable, Sendable, CustomStringConvertible {
    var count: Int
    var digest: UInt64

    init(_ data: Data) {
        count = data.count
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        data.withUnsafeBytes { bytes in
            for byte in bytes { hash = (hash ^ UInt64(byte)) &* 0x100_0000_01b3 }
        }
        digest = hash
    }

    var description: String {
        "\(count / 1024) KB #\(String(String(digest, radix: 16).prefix(6)))"
    }
}

/// An item's values with the blob's bytes and relationships as keys, as a merge snapshot holds them, for
/// merging without a store.
struct Draft {
    var title = Scenario.baseTitle
    var steps = Scenario.baseSteps
    var spec = Scenario.baseSpec
    var labels: Set<String> = [Scenario.baseLabel]
    var blob: Data? = Scenario.baseBlob

    init() {}

    init(_ snapshot: Item.MergeSnapshot) {
        title = snapshot.title
        steps = snapshot.steps
        spec = snapshot.spec
        labels = snapshot.labels
        blob = snapshot.blob
    }

    mutating func apply(_ kind: DataKind, by editor: Int) {
        switch kind {
        case .string: title = Scenario.uppercasing(title, word: Scenario.stringWords[editor])
        case .strings: steps.append("editor-\(editor)")
        case .codable: Scenario.edit(&spec, by: editor)
        case .relationship: labels.insert("editor-\(editor)")
        case .blob:
            if editor == 0 {
                blob = Scenario.editedBlob
            } else {
                title = Scenario.uppercasing(title, word: Scenario.blobTitleWords[editor])
            }
        }
    }

    var values: ItemValues {
        ItemValues(title: title, steps: steps, spec: spec, labels: labels, blob: blob.map(BlobSummary.init))
    }

    /// As a snapshot, with each label's name standing in for its object's key.
    var snapshot: Item.MergeSnapshot {
        Item.MergeSnapshot(key: "rules", title: title, steps: steps, spec: spec, labels: labels, blob: blob)
    }
}

extension Spec {
    /// Sorted-key JSON, so two specs read the same way when they're equal.
    var text: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return (try? encoder.encode(self)).map { String(decoding: $0, as: UTF8.self) } ?? "?"
    }
}

struct LabError: LocalizedError {
    var message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

/// A test that can't run here, such as a CloudKit test without CloudKit set up.
struct LabSkip: Error {
    var reason: String
}
