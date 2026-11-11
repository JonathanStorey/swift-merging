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

/// The same Codable struct merged with `.total`, once favoring each side, so a clash never stops the merge.
@Model @MergeableModel
final class Canvas {
    @Merge(.total(favoring: .theirs)) var shared: Layout = Layout()
    @Merge(.total(favoring: .ours)) var draft: Layout = Layout()

    init() {}
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

    /// Both contexts set the same caption differently and each changes a part of its own. The clash goes to
    /// the side each property favors, and every other edit lands.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func totalMergesACodablePropertyAndSettlesClashesByItsSide() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "total-\(UUID().uuidString).store")
        let container = try ModelContainer(for: Canvas.self, configurations: ModelConfiguration(url: url))
        container.mainContext.autosaveEnabled = false
        let board = Canvas()
        container.mainContext.insert(board)
        try container.mainContext.save()
        let id = board.persistentModelID
        let coordinator = try MergeCoordinator(container: container, types: [Canvas.self])

        board.shared.size.width = 5
        board.shared.caption = "ours"
        board.draft.size.width = 5
        board.draft.caption = "ours"
        let context = ModelContext(container)
        context.author = "sync"
        var descriptor = FetchDescriptor<Canvas>(predicate: #Predicate { $0.persistentModelID == id })
        descriptor.fetchLimit = 1
        let theirs = try #require(try context.fetch(descriptor).first)
        theirs.shared.options["theirs"] = 1
        theirs.shared.caption = "theirs"
        theirs.draft.points.append(Layout.Point(x: 2, y: 2))
        theirs.draft.caption = "theirs"
        try context.save()

        try coordinator.mergePendingChanges()
        try container.mainContext.save()
        try coordinator.mergePendingChanges()

        let reader = ModelContext(container)
        let (shared, draft) = try withExtendedLifetime(reader) {
            let stored = try #require(try reader.fetch(descriptor).first)
            return (stored.shared, stored.draft)
        }
        #expect(shared.size.width == 5)
        #expect(shared.options == ["theirs": 1])
        #expect(shared.caption == "theirs")
        #expect(draft.size.width == 5)
        #expect(draft.points == [Layout.Point(x: 2, y: 2)])
        #expect(draft.caption == "ours")
    }
}
#endif
