import Foundation
import Observation

/// What the live diagram shows for the running test: each editor or device, the store or iCloud between
/// them, and what everyone is waiting for.
@MainActor @Observable
final class LiveBoard {
    enum State: Equatable {
        case idle
        /// Has an edit it hasn't saved.
        case editing
        /// Saving, or sending its change.
        case sending
        /// Receiving another's change.
        case receiving
        /// Merging two versions.
        case merging
        /// Waiting on something else.
        case waiting
        /// Can't reach the server.
        case offline
        case done
        case failed

        var symbol: String? {
            switch self {
            case .idle: nil
            case .editing: "pencil.circle.fill"
            case .sending: "arrow.up.circle.fill"
            case .receiving: "arrow.down.circle.fill"
            case .merging: "arrow.triangle.merge"
            case .waiting: "hourglass.circle.fill"
            case .offline: "airplane.circle.fill"
            case .done: "checkmark.circle.fill"
            case .failed: "exclamationmark.triangle.fill"
            }
        }
    }

    /// The test the diagram is showing.
    private(set) var test: LabTest?
    /// Each editor's or device's state, by index.
    private(set) var editors: [State] = []
    /// The store, for one-store stages, or iCloud, for CloudKit stages.
    var hub = State.idle
    /// What the test is waiting for, if anything.
    var waitingFor: String?
    /// When the wait started, for the timer beside it.
    private(set) var waitingSince: Date?

    func show(_ test: LabTest) {
        self.test = test
        editors = Array(repeating: .idle, count: test.stage.editors)
        hub = .idle
        waitingFor = nil
        waitingSince = nil
    }

    func set(_ editor: Int, _ state: State) {
        guard editors.indices.contains(editor) else { return }
        editors[editor] = state
    }

    func setAll(_ state: State) {
        editors = editors.map { _ in state }
    }

    func wait(for description: String?) {
        waitingFor = description
        waitingSince = description == nil ? nil : .now
    }

    /// Ends the test's diagram: every node done, or the hub marked failed.
    func finish(passed: Bool) {
        wait(for: nil)
        setAll(passed ? .done : .idle)
        hub = passed ? .done : .failed
    }
}
