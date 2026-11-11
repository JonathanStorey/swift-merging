import SwiftUI

/// A test's status as a symbol: an empty circle to start, a pulsing one while it runs, then a check, a cross,
/// or a dash.
struct StatusIcon: View {
    let status: TestResult.Status

    var body: some View {
        Image(systemName: symbol)
            .foregroundStyle(color)
            .symbolEffect(.pulse, isActive: status == .running)
            .contentTransition(.symbolEffect(.replace))
            .accessibilityLabel(label)
    }

    private var symbol: String {
        switch status {
        case .pending: "circle"
        case .running: "circle.dotted.circle"
        case .passed: "checkmark.circle.fill"
        case .failed: "xmark.circle.fill"
        case .skipped: "minus.circle.fill"
        }
    }

    private var color: Color {
        switch status {
        case .pending: .secondary
        case .running: .blue
        case .passed: .green
        case .failed: .red
        case .skipped: .orange
        }
    }

    private var label: String {
        switch status {
        case .pending: "Not run"
        case .running: "Running"
        case .passed: "Passed"
        case .failed: "Failed"
        case .skipped: "Skipped"
        }
    }
}

extension LiveBoard.State {
    var color: Color {
        switch self {
        case .idle: .secondary
        case .editing: .purple
        case .sending, .receiving: .blue
        case .merging: .indigo
        case .waiting: .orange
        case .offline: .orange
        case .done: .green
        case .failed: .red
        }
    }

    var isActive: Bool {
        switch self {
        case .sending, .receiving, .merging, .waiting: true
        default: false
        }
    }
}
