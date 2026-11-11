#if canImport(SwiftData)
import Foundation
@testable import MergingSwiftData
import SwiftData
import Testing

/// A Codable struct as one property, which SwiftData stores as a composite attribute: one column per part.
struct Layout: Codable, Equatable, Sendable {
    struct Size: Codable, Equatable, Sendable {
        var width = 1.0
        var height = 1.0
    }

    struct Point: Codable, Equatable, Sendable {
        var x = 0
        var y = 0
    }

    var size = Size()
    var options: [String: Int] = [:]
    var points: [Point] = []
    var caption = ""
}

@Model @MergeableModel
final class Sheet {
    @Merge(.byNode) var layout: Layout = Layout()
    var name = "sheet"

    init() {}
}

/// What SwiftData can't store as a composite attribute: an optional and an enum inside the struct.
struct Preferences: Codable, Equatable, Sendable {
    enum Theme: String, Codable, Sendable { case light, dark }

    var theme = Theme.light
    var nickname: String? = nil
    var limits: [String: Int] = [:]
}

/// The same kind of value kept as JSON, which SwiftData stores as one `Data` column.
@Model @MergeableModel
final class Profile {
    @Merge(.json(Preferences.self)) var preferencesJSON: Data = Data()

    var preferences: Preferences {
        get { JSONDataMerge<Preferences>.decode(preferencesJSON) ?? Preferences() }
        set { preferencesJSON = JSONDataMerge<Preferences>.encode(newValue) }
    }

    init() {
        preferencesJSON = JSONDataMerge<Preferences>.encode(Preferences())
    }
}

@MainActor
@Suite struct CodablePropertyTests {
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    func makeSheet() throws -> (ModelContainer, Sheet, PersistentIdentifier) {
        let url = FileManager.default.temporaryDirectory.appending(path: "codable-\(UUID().uuidString).store")
        let container = try ModelContainer(for: Sheet.self, configurations: ModelConfiguration(url: url))
        container.mainContext.autosaveEnabled = false
        let sheet = Sheet()
        sheet.layout.options = ["base": 0]
        container.mainContext.insert(sheet)
        try container.mainContext.save()
        return (container, sheet, sheet.persistentModelID)
    }

    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    func theirEdit(_ container: ModelContainer, _ id: PersistentIdentifier, _ edit: (Sheet) -> Void) throws {
        let context = ModelContext(container)
        context.author = "sync"
        var descriptor = FetchDescriptor<Sheet>(predicate: #Predicate { $0.persistentModelID == id })
        descriptor.fetchLimit = 1
        edit(try #require(try context.fetch(descriptor).first))
        try context.save()
    }

    /// What the history and the store report for a change to part of a Codable property.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func spikeWhatAChangeToACodablePropertyReports() throws {
        let (container, _, id) = try makeSheet()
        let coordinator = try MergeCoordinator(container: container, types: [Sheet.self])
        try theirEdit(container, id) { $0.layout.options["theirs"] = 1 }

        let transactions = try ModelContext(container).fetchHistory(HistoryDescriptor<DefaultHistoryTransaction>())
        for transaction in transactions {
            for change in transaction.changes {
                if case .update(let update) = change, let update = update as? DefaultHistoryUpdate<Sheet> {
                    print("Spike: updated attributes =", update.updatedAttributes.map { String(describing: $0) })
                }
            }
        }
        print("Spike: snapshot key paths =", Sheet.mergeKeyPaths.map { String(describing: $0) })
        for record in coordinator.capture.records(forObject: MergeRelationship.key(id)) {
            for (key, value) in record.base.sorted(by: { $0.key < $1.key }) {
                print("Spike: before", key, "=", type(of: value), value)
            }
            for (key, value) in record.new.sorted(by: { $0.key < $1.key }) {
                print("Spike: after", key, "=", type(of: value), value)
            }
        }
    }

    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func editsToDifferentPartsOfACodablePropertyCombine() throws {
        let (container, sheet, id) = try makeSheet()
        let coordinator = try MergeCoordinator(container: container, types: [Sheet.self])
        sheet.layout.size.width = 5
        try theirEdit(container, id) { $0.layout.options["theirs"] = 1 }
        try coordinator.mergePendingChanges()
        try container.mainContext.save()
        try coordinator.mergePendingChanges()

        let reader = ModelContext(container)
        var descriptor = FetchDescriptor<Sheet>(predicate: #Predicate { $0.persistentModelID == id })
        descriptor.fetchLimit = 1
        let saved = try withExtendedLifetime(reader) { try #require(try reader.fetch(descriptor).first).layout }
        #expect(saved.size.width == 5)
        #expect(saved.options == ["base": 0, "theirs": 1])
    }

    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func twoSavesToDifferentPartsOfACodablePropertyBothCombine() throws {
        let (container, sheet, id) = try makeSheet()
        let coordinator = try MergeCoordinator(container: container, types: [Sheet.self])
        sheet.layout.size.width = 5
        try theirEdit(container, id) { $0.layout.options["theirs"] = 1 }
        try theirEdit(container, id) { $0.layout.points.append(Layout.Point(x: 2, y: 2)) }
        try coordinator.mergePendingChanges()
        try container.mainContext.save()
        try coordinator.mergePendingChanges()

        let reader = ModelContext(container)
        var descriptor = FetchDescriptor<Sheet>(predicate: #Predicate { $0.persistentModelID == id })
        descriptor.fetchLimit = 1
        let saved = try withExtendedLifetime(reader) { try #require(try reader.fetch(descriptor).first).layout }
        #expect(saved.size.width == 5)
        #expect(saved.options == ["base": 0, "theirs": 1])
        #expect(saved.points == [Layout.Point(x: 2, y: 2)])
    }

    /// An optional and an enum inside a value kept as JSON survive history reads, and edits to different
    /// parts combine.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func aValueKeptAsJSONMergesWithOptionalsAndEnums() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "json-\(UUID().uuidString).store")
        let container = try ModelContainer(for: Profile.self, configurations: ModelConfiguration(url: url))
        container.mainContext.autosaveEnabled = false
        let profile = Profile()
        container.mainContext.insert(profile)
        try container.mainContext.save()
        let id = profile.persistentModelID
        let coordinator = try MergeCoordinator(container: container, types: [Profile.self])

        profile.preferences.theme = .dark
        let other = ModelContext(container)
        other.author = "sync"
        var descriptor = FetchDescriptor<Profile>(predicate: #Predicate { $0.persistentModelID == id })
        descriptor.fetchLimit = 1
        let theirs = try #require(try other.fetch(descriptor).first)
        theirs.preferences.nickname = "theirs"
        theirs.preferences.limits["daily"] = 3
        try other.save()

        try coordinator.mergePendingChanges()
        try container.mainContext.save()
        try coordinator.mergePendingChanges()

        let reader = ModelContext(container)
        let saved = try withExtendedLifetime(reader) { try #require(try reader.fetch(descriptor).first).preferences }
        #expect(saved == Preferences(theme: .dark, nickname: "theirs", limits: ["daily": 3]))
    }
}
#endif
