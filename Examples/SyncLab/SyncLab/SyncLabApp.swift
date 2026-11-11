import SwiftUI

@main
struct SyncLabApp: App {
    @State private var runner = Runner()

    init() {
        SyncMonitor.shared.start()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(runner)
                .environment(CloudLab.shared)
                .task { await Autorun.startIfRequested(runner) }
        }
    }
}

/// `-autorun local` runs every stage that needs no CloudKit, prints each result, and quits, for CI.
/// `-autorun all` runs everything.
@MainActor
enum Autorun {
    static func startIfRequested(_ runner: Runner) async {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-autorun"), arguments.indices.contains(index + 1) else { return }
        let everything = arguments[index + 1] == "all"
        let tests = runner.tests.filter { everything || !$0.stage.needsCloudKit }
        emit("SYNCLAB START \(tests.count) tests")
        await runner.run(tests)?.value

        var counts: [TestResult.Status: Int] = [:]
        for test in tests {
            let result = runner.result(for: test)
            counts[result.status, default: 0] += 1
            let duration = String(format: "%.1fs", result.duration ?? 0)
            emit("SYNCLAB \(String(describing: result.status).uppercased()) \(test.stage.title) / \(test.kind.title) (\(duration))")
            for failure in result.failures { emit("    - \(failure)") }
            if result.status == .failed {
                for line in result.lines { emit("      \(line)") }
            }
        }
        let failed = counts[.failed, default: 0]
        emit("SYNCLAB DONE passed=\(counts[.passed, default: 0]) failed=\(failed) skipped=\(counts[.skipped, default: 0])")
        exit(failed == 0 ? 0 : 1)
    }

    private static func emit(_ line: String) {
        print(line)
        fflush(stdout)
    }
}
