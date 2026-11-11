import Foundation
import Observation

/// Runs tests one at a time, in order, and keeps each one's result.
@MainActor @Observable
final class Runner {
    let tests = LabTest.all
    let board = LiveBoard()
    private(set) var results: [String: TestResult] = [:]
    private(set) var runningID: String?
    private(set) var isRunning = false
    @ObservationIgnored private var task: Task<Void, Never>?

    init() {
        for test in tests { results[test.id] = TestResult() }
    }

    func result(for test: LabTest) -> TestResult {
        results[test.id]!
    }

    func tests(in stage: Stage) -> [LabTest] {
        tests.filter { $0.stage == stage }
    }

    /// Runs `selection` one test after another. Returns the task, to wait for it.
    @discardableResult
    func run(_ selection: [LabTest]) -> Task<Void, Never>? {
        guard !isRunning, !selection.isEmpty else { return nil }
        for test in selection { result(for: test).reset() }
        isRunning = true
        let task = Task { [weak self] in
            for test in selection {
                guard let self, !Task.isCancelled else { break }
                await self.execute(test)
                // A beat between tests, so each one visibly checks off.
                try? await Task.sleep(for: .milliseconds(300))
            }
            self?.runningID = nil
            self?.isRunning = false
        }
        self.task = task
        return task
    }

    func stop() {
        task?.cancel()
    }

    private func execute(_ test: LabTest) async {
        let result = result(for: test)
        runningID = test.id
        board.show(test)
        result.start()
        let lab = LabContext(result: result, board: board)
        do {
            let failures = try await test.run(lab)
            result.finish(failures.isEmpty ? .passed : .failed, failures: failures)
        } catch is CancellationError {
            result.finish(.skipped, failures: ["Stopped"])
        } catch let skip as LabSkip {
            result.finish(.skipped, failures: [skip.reason])
        } catch {
            result.finish(.failed, failures: [error.localizedDescription])
        }
        board.finish(passed: result.status == .passed)
    }
}
