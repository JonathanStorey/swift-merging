import SwiftUI

struct TestDetailView: View {
    let test: LabTest
    @Environment(Runner.self) private var runner

    var body: some View {
        let result = runner.result(for: test)
        List {
            Section {
                HStack(spacing: 12) {
                    StatusIcon(status: result.status)
                        .font(.largeTitle)
                    VStack(alignment: .leading) {
                        Text(test.kind.title).font(.headline)
                        Text(test.stage.title).foregroundStyle(.secondary)
                        if let timing = test.timing {
                            Label(timing.title, systemImage: timing.symbol)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Text(test.kind.strategy)
                    .font(.footnote.monospaced())
                    .foregroundStyle(.secondary)
            }

            if runner.runningID == test.id {
                Section("Live") {
                    LiveDiagramView()
                }
            }

            Section("Steps") {
                ForEach(Array(test.steps.enumerated()), id: \.offset) { index, step in
                    Label(step, systemImage: "\(index + 1).circle")
                }
                Label("Every editor's change is kept", systemImage: "checkmark.seal")
            }

            if !result.failures.isEmpty {
                Section(result.status == .skipped ? "Skipped" : "What went wrong") {
                    ForEach(result.failures, id: \.self) { failure in
                        Label(failure, systemImage: result.status == .skipped ? "minus.circle" : "exclamationmark.triangle.fill")
                            .foregroundStyle(result.status == .skipped ? .orange : .red)
                            .font(.footnote)
                    }
                }
            }

            if !result.lines.isEmpty {
                Section("Log") {
                    ForEach(Array(result.lines.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                    }
                }
            }
        }
        .navigationTitle(test.kind.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Button("Run", systemImage: "play.fill") { runner.run([test]) }
                .disabled(runner.isRunning)
        }
    }
}
