import SwiftUI

struct TestRow: View {
    let test: LabTest
    @Environment(Runner.self) private var runner

    var body: some View {
        let result = runner.result(for: test)
        HStack(spacing: 12) {
            StatusIcon(status: result.status)
                .font(.title3)
                .frame(width: 26)
            Image(systemName: test.kind.symbol)
                .foregroundStyle(.tint)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(test.kind.title)
                if let timing = test.timing {
                    Label(timing.title, systemImage: timing.symbol)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text(test.kind.strategy)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            Spacer(minLength: 4)
            if let duration = result.duration {
                Text(String(format: "%.1fs", duration))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .animation(.default, value: result.status)
    }
}

/// A stage's title, what it does, and a small picture of who talks to what.
struct StageHeader: View {
    let stage: Stage
    let run: () -> Void
    let disabled: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(stage.title, systemImage: stage.symbol)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Spacer()
                Button("Run", systemImage: "play.fill", action: run)
                    .labelStyle(.iconOnly)
                    .disabled(disabled)
                    .accessibilityLabel("Run \(stage.title)")
            }
            StageSketch(stage: stage)
            Text(stage.subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .textCase(nil)
        .padding(.vertical, 4)
    }
}

/// Who talks to what in a stage, drawn with symbols.
struct StageSketch: View {
    let stage: Stage

    var body: some View {
        HStack(spacing: 6) {
            switch stage {
            case .rules:
                Image(systemName: "doc.text")
                Image(systemName: "arrow.triangle.branch")
                Image(systemName: "doc.on.doc")
                Image(systemName: "arrow.triangle.merge")
                Image(systemName: "checkmark.seal")
            case .oneStoreTwoEditors, .oneStoreThreeEditors:
                ForEach(0..<stage.editors, id: \.self) { _ in Image(systemName: "person.crop.circle") }
                Image(systemName: "arrow.right")
                Image(systemName: "externaldrive.fill")
            case .twoStores, .threeStores:
                ForEach(0..<stage.editors, id: \.self) { index in
                    HStack(spacing: 1) {
                        Image(systemName: "iphone")
                        Text(Device.names[index]).font(.caption2.weight(.semibold))
                    }
                }
                Image(systemName: "arrow.left.arrow.right")
                Image(systemName: "icloud.fill")
            }
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .accessibilityHidden(true)
    }
}
