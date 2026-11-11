#if canImport(SwiftData)
import Foundation
import MergingSwiftData
import SwiftData
import Testing

// Probes for where SwiftData stops the app on a Codable property: in its own saves and fetches, in reading
// the store's history, or only with merging on. A crash ends the process, so CI runs each probe on its
// own, with SWIFTDATA_PROBES set, and reports which ones survived. Without that variable they're skipped.

struct ProbePlainValue: Codable, Equatable, Sendable {
    var width = 1.0
    var caption = ""
}

struct ProbeOptionalValue: Codable, Equatable, Sendable {
    var width = 1.0
    var caption: String? = nil
}

enum ProbeShape: String, Codable, Sendable {
    case circle, star
}

struct ProbeEnumValue: Codable, Equatable, Sendable {
    var width = 1.0
    var shape = ProbeShape.circle
}

struct ProbeIdentifier: Codable, Equatable, Sendable {
    var id = "a"
}

/// A struct with only plain fields: the control.
@Model @MergeableModel final class ProbePlain {
    @Merge(.byNode) var value: ProbePlainValue = ProbePlainValue()
    init() {}
}

/// A struct holding an optional.
@Model @MergeableModel final class ProbeOptional {
    @Merge(.byNode) var value: ProbeOptionalValue = ProbeOptionalValue()
    init() {}
}

/// A struct holding an enum.
@Model @MergeableModel final class ProbeEnum {
    @Merge(.byNode) var value: ProbeEnumValue = ProbeEnumValue()
    init() {}
}

/// An optional struct, as in https://developer.apple.com/forums/thread/784036.
@Model @MergeableModel final class ProbeTopOptional {
    var value: ProbeIdentifier? = nil
    init() {}
}

/// An enum as a property of its own, not inside a struct.
@Model @MergeableModel final class ProbeTopEnum {
    var shape: ProbeShape = ProbeShape.circle
    init() {}
}

@MainActor
@Suite(.enabled(if: ProcessInfo.processInfo.environment["SWIFTDATA_PROBES"] != nil))
struct SwiftDataProbes {
    enum Step {
        /// Insert, save, change in another context, save, fetch: SwiftData alone, no history.
        case plain
        /// The same, then read the history and each update's changed attributes, as merging does.
        case history
        /// The same, with a merge coordinator watching, as `enableMerging` sets up.
        case merging
    }

    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    func probe<Model: MergeableModel>(_ name: String, _ step: Step, make: () -> Model, edit: (Model) -> Void,
                                      describe: (Model) -> String) throws {
        func reached(_ point: String) {
            print("PROBE \(name): \(point)")
            fflush(stdout)
        }
        let url = FileManager.default.temporaryDirectory.appending(path: "probe-\(UUID().uuidString).store")
        reached("opening the store")
        let container = try ModelContainer(for: Model.self, configurations: ModelConfiguration(url: url))
        container.mainContext.autosaveEnabled = false
        let coordinator = step == .merging ? try MergeCoordinator(container: container, types: [Model.self]) : nil
        coordinator?.startObserving()

        reached("inserting")
        container.mainContext.insert(make())
        try container.mainContext.save()

        if step != .plain {
            reached("reading history after the insert")
            _ = try ModelContext(container).fetchHistory(HistoryDescriptor<DefaultHistoryTransaction>())
        }

        reached("changing it in another context")
        let other = ModelContext(container)
        other.author = "probe"
        let object = try #require(try other.fetch(FetchDescriptor<Model>()).first)
        edit(object)
        try other.save()

        if step != .plain {
            reached("reading history after the change")
            let transactions = try ModelContext(container).fetchHistory(HistoryDescriptor<DefaultHistoryTransaction>())
            reached("reading each update's changed attributes")
            for transaction in transactions {
                for change in transaction.changes {
                    if case .update(let update) = change, let update = update as? DefaultHistoryUpdate<Model> {
                        reached("updated attributes: \(update.updatedAttributes.map { String(describing: $0) })")
                    }
                }
            }
        }

        if let coordinator {
            reached("merging")
            try coordinator.mergePendingChanges()
            try container.mainContext.save()
        }

        reached("fetching in a fresh context")
        let reader = ModelContext(container)
        let saved = try withExtendedLifetime(reader) { try #require(try reader.fetch(FetchDescriptor<Model>()).first).map(describe) }
        reached("survived; stored value \(saved)")
    }

    // MARK: - SwiftData alone

    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func plainPlain() throws {
        try probe("plainPlain", .plain, make: ProbePlain.init, edit: { $0.value.caption = "set" }, describe: { "\($0.value)" })
    }

    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func plainOptional() throws {
        try probe("plainOptional", .plain, make: ProbeOptional.init, edit: { $0.value.caption = "set" }, describe: { "\($0.value)" })
    }

    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func plainEnum() throws {
        try probe("plainEnum", .plain, make: ProbeEnum.init, edit: { $0.value.shape = .star }, describe: { "\($0.value)" })
    }

    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func plainTopOptional() throws {
        try probe("plainTopOptional", .plain, make: ProbeTopOptional.init, edit: { $0.value = ProbeIdentifier(id: "b") },
                  describe: { "\(String(describing: $0.value))" })
    }

    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func plainTopEnum() throws {
        try probe("plainTopEnum", .plain, make: ProbeTopEnum.init, edit: { $0.shape = .star }, describe: { "\($0.shape)" })
    }

    // MARK: - Reading history, as merging does

    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func historyPlain() throws {
        try probe("historyPlain", .history, make: ProbePlain.init, edit: { $0.value.caption = "set" }, describe: { "\($0.value)" })
    }

    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func historyOptional() throws {
        try probe("historyOptional", .history, make: ProbeOptional.init, edit: { $0.value.caption = "set" }, describe: { "\($0.value)" })
    }

    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func historyEnum() throws {
        try probe("historyEnum", .history, make: ProbeEnum.init, edit: { $0.value.shape = .star }, describe: { "\($0.value)" })
    }

    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func historyTopOptional() throws {
        try probe("historyTopOptional", .history, make: ProbeTopOptional.init, edit: { $0.value = ProbeIdentifier(id: "b") },
                  describe: { "\(String(describing: $0.value))" })
    }

    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func historyTopEnum() throws {
        try probe("historyTopEnum", .history, make: ProbeTopEnum.init, edit: { $0.shape = .star }, describe: { "\($0.shape)" })
    }

    // MARK: - With merging on

    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func mergingPlain() throws {
        try probe("mergingPlain", .merging, make: ProbePlain.init, edit: { $0.value.caption = "set" }, describe: { "\($0.value)" })
    }

    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func mergingOptional() throws {
        try probe("mergingOptional", .merging, make: ProbeOptional.init, edit: { $0.value.caption = "set" }, describe: { "\($0.value)" })
    }

    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func mergingEnum() throws {
        try probe("mergingEnum", .merging, make: ProbeEnum.init, edit: { $0.value.shape = .star }, describe: { "\($0.value)" })
    }
}
#endif
