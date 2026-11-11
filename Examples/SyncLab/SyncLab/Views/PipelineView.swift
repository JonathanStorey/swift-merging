import SwiftUI

/// The stages as a row of symbols joined by lines, each filling in as its tests check off.
struct PipelineView: View {
    @Environment(Runner.self) private var runner

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 0) {
                ForEach(Stage.allCases) { stage in
                    if stage != Stage.allCases.first {
                        Capsule()
                            .fill(connectorColor(before: stage))
                            .frame(height: 3)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 21)
                            .animation(.easeInOut, value: connectorColor(before: stage))
                    }
                    StageNode(stage: stage, state: state(of: stage), progress: progress(of: stage))
                }
            }
            let checked = runner.tests.filter { runner.result(for: $0).status == .passed }.count
            ProgressView(value: Double(checked), total: Double(runner.tests.count)) {
                Text("\(checked) of \(runner.tests.count) checked off")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .tint(.green)
        }
        .padding(.vertical, 6)
    }

    private func statuses(of stage: Stage) -> [TestResult.Status] {
        runner.tests(in: stage).map { runner.result(for: $0).status }
    }

    private func progress(of stage: Stage) -> Double {
        let all = statuses(of: stage)
        return Double(all.filter { $0 == .passed }.count) / Double(max(all.count, 1))
    }

    private func state(of stage: Stage) -> TestResult.Status {
        let all = statuses(of: stage)
        if all.contains(.running) { return .running }
        if all.contains(.failed) { return .failed }
        if all.allSatisfy({ $0 == .passed }) { return .passed }
        if all.allSatisfy({ $0 == .passed || $0 == .skipped }), all.contains(.skipped) { return .skipped }
        return .pending
    }

    private func connectorColor(before stage: Stage) -> Color {
        guard let previous = Stage(rawValue: stage.rawValue - 1) else { return .secondary }
        return state(of: previous) == .passed ? .green : Color.secondary.opacity(0.3)
    }
}

private struct StageNode: View {
    let stage: Stage
    let state: TestResult.Status
    let progress: Double

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.12))
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(color, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut, value: progress)
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(color)
                    .symbolEffect(.pulse, isActive: state == .running)
                    .contentTransition(.symbolEffect(.replace))
            }
            .frame(width: 44, height: 44)
            Text(stage.shortTitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(stage.title), \(Int(progress * 100)) percent")
    }

    private var symbol: String {
        switch state {
        case .passed: "checkmark"
        case .failed: "xmark"
        default: stage.symbol
        }
    }

    private var color: Color {
        switch state {
        case .pending: .secondary
        case .running: .blue
        case .passed: .green
        case .failed: .red
        case .skipped: .orange
        }
    }
}
