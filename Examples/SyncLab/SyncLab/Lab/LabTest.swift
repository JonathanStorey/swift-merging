import Foundation

/// The lab's stages, run in order: merges with no store, then one store with several editors, then several
/// stores syncing through CloudKit.
enum Stage: Int, CaseIterable, Identifiable, Sendable {
    case rules, oneStoreTwoEditors, oneStoreThreeEditors, twoStores, threeStores

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .rules: "Merge rules"
        case .oneStoreTwoEditors: "One store, 2 editors"
        case .oneStoreThreeEditors: "One store, 3 editors"
        case .twoStores: "2 stores via CloudKit"
        case .threeStores: "3 stores via CloudKit"
        }
    }

    var shortTitle: String {
        switch self {
        case .rules: "Rules"
        case .oneStoreTwoEditors: "1 store ×2"
        case .oneStoreThreeEditors: "1 store ×3"
        case .twoStores: "2 stores"
        case .threeStores: "3 stores"
        }
    }

    var subtitle: String {
        switch self {
        case .rules:
            "Merges the model's snapshots with no store: 3-way from a base, with two and three editors, and 2-way with no base, which may refuse but must never drop an edit."
        case .oneStoreTwoEditors:
            "The main context edits without saving while a background context edits and saves. The main context's save merges first."
        case .oneStoreThreeEditors:
            "As before, with two background contexts saving one after the other before the main context saves."
        case .twoStores:
            "Two store files on the same CloudKit container and zone stand in for two devices. Each test uses a different timing."
        case .threeStores:
            "Three store files, three devices. The timings shift by one, so each kind of data meets a different one than with two stores."
        }
    }

    var symbol: String {
        switch self {
        case .rules: "arrow.triangle.merge"
        case .oneStoreTwoEditors: "person.2.fill"
        case .oneStoreThreeEditors: "person.3.fill"
        case .twoStores: "icloud.fill"
        case .threeStores: "point.3.filled.connected.trianglepath.dotted"
        }
    }

    var editors: Int {
        switch self {
        case .rules, .oneStoreTwoEditors, .twoStores: 2
        case .oneStoreThreeEditors, .threeStores: 3
        }
    }

    var needsCloudKit: Bool { self == .twoStores || self == .threeStores }

    /// Who editor `index` is in this stage.
    func editorName(_ index: Int) -> String {
        switch self {
        case .rules: ["Ours", "Theirs", "Theirs, a second save"][index]
        case .oneStoreTwoEditors, .oneStoreThreeEditors: ["Main context", "Background 1", "Background 2"][index]
        case .twoStores, .threeStores: Device.names[index]
        }
    }

    /// Where the CloudKit stages start in the timing rotation.
    var timingOffset: Int { self == .threeStores ? 1 : 0 }
}

/// When the devices in a CloudKit stage save their edits, relative to each other and to sync.
enum Timing: String, CaseIterable, Sendable {
    /// Every device saves in the same instant, so the exports race at the server.
    case together
    /// The other devices edit without saving while device A's change arrives, then save.
    case whileEditing
    /// The other devices go offline, edit and save, and come back once device A has exported.
    case offline

    var title: String {
        switch self {
        case .together: "Everyone saves at once"
        case .whileEditing: "Edit while A's change arrives"
        case .offline: "Edit offline, then reconnect"
        }
    }

    var symbol: String {
        switch self {
        case .together: "bolt.horizontal.fill"
        case .whileEditing: "keyboard"
        case .offline: "airplane"
        }
    }

    static func rotation(_ index: Int) -> Timing { allCases[index % allCases.count] }
}

struct LabTest: Identifiable, Hashable, Sendable {
    let stage: Stage
    let kind: DataKind
    let timing: Timing?

    var id: String { "\(stage.rawValue)-\(kind.rawValue)" }

    static let all: [LabTest] = Stage.allCases.flatMap { stage in
        DataKind.allCases.enumerated().map { index, kind in
            LabTest(stage: stage, kind: kind, timing: stage.needsCloudKit ? .rotation(index + stage.timingOffset) : nil)
        }
    }

    /// What each editor does, in order.
    var steps: [String] {
        (0..<stage.editors).map { "\(stage.editorName($0)) \(kind.editSummary($0))" }
    }

    /// Runs the test, returning what went wrong, or nothing when it passed.
    @MainActor func run(_ lab: LabContext) async throws -> [String] {
        switch stage {
        case .rules:
            return RuleLab.run(kind, lab)
        case .oneStoreTwoEditors, .oneStoreThreeEditors:
            return try await StoreLab.run(kind, editors: stage.editors, lab)
        case .twoStores, .threeStores:
            return try await CloudLab.shared.run(kind, timing: timing ?? .together, devices: stage.editors, lab)
        }
    }
}

/// What a running test reports to: its log, and the live diagram.
@MainActor
struct LabContext {
    let result: TestResult
    let board: LiveBoard

    func log(_ line: String) { result.log(line) }
}
