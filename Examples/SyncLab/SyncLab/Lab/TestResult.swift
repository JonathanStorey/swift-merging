import Foundation
import Observation

@MainActor @Observable
final class TestResult {
    enum Status: Hashable {
        case pending, running, passed, failed, skipped
    }

    private(set) var status = Status.pending
    private(set) var startedAt: Date?
    private(set) var duration: TimeInterval?
    private(set) var lines: [String] = []
    private(set) var failures: [String] = []

    func start() {
        status = .running
        startedAt = .now
        duration = nil
        lines = []
        failures = []
    }

    func reset() {
        status = .pending
        startedAt = nil
        duration = nil
        lines = []
        failures = []
    }

    func log(_ line: String) {
        let elapsed = startedAt.map { Date.now.timeIntervalSince($0) } ?? 0
        lines.append(String(format: "%6.1fs  ", elapsed) + line)
    }

    func finish(_ status: Status, failures: [String] = []) {
        self.status = status
        self.failures = failures
        duration = startedAt.map { Date.now.timeIntervalSince($0) }
    }
}
