import SwiftUI

/// The running test as a diagram: each editor or device on the left, linked to the store or to iCloud on the
/// right. Badges show what each one is doing, links light up while changes travel, and a timer runs while the
/// test waits.
struct LiveDiagramView: View {
    @Environment(Runner.self) private var runner
    @Environment(CloudLab.self) private var cloud

    var body: some View {
        let board = runner.board
        if let test = board.test {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 6) {
                    Image(systemName: test.kind.symbol)
                    Text("\(test.stage.title) · \(test.kind.title)")
                        .lineLimit(1)
                    if let timing = test.timing {
                        Spacer(minLength: 4)
                        Image(systemName: timing.symbol)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel(timing.title)
                    }
                }
                .font(.subheadline.weight(.semibold))

                HStack(alignment: .center, spacing: 0) {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(Array(board.editors.indices), id: \.self) { index in
                            HStack(spacing: 0) {
                                NodeView(symbol: nodeSymbol(test.stage), name: test.stage.editorName(index),
                                         state: state(of: index, in: test.stage))
                                LinkView(state: state(of: index, in: test.stage), cloud: test.stage.needsCloudKit)
                            }
                        }
                    }
                    HubView(stage: test.stage, state: board.hub)
                }

                if let waiting = board.waitingFor, let since = board.waitingSince {
                    TimelineView(.periodic(from: since, by: 1)) { context in
                        Label {
                            Text("Waiting until \(waiting) · \(Int(context.date.timeIntervalSince(since)))s")
                        } icon: {
                            Image(systemName: "hourglass")
                                .symbolEffect(.pulse)
                        }
                        .font(.footnote)
                        .foregroundStyle(.orange)
                    }
                }
            }
            .padding(.vertical, 6)
            .animation(.easeInOut(duration: 0.25), value: board.editors)
            .animation(.easeInOut(duration: 0.25), value: board.hub)
        } else {
            Label("Run a test to watch it here", systemImage: "play.circle")
                .foregroundStyle(.secondary)
        }
    }

    private func nodeSymbol(_ stage: Stage) -> String {
        switch stage {
        case .rules: "doc.text"
        case .oneStoreTwoEditors, .oneStoreThreeEditors: "person.crop.circle"
        case .twoStores, .threeStores: "iphone"
        }
    }

    /// A device's state is what CloudKit says it's doing, when it's doing something, and otherwise what the
    /// test set.
    private func state(of index: Int, in stage: Stage) -> LiveBoard.State {
        let set = runner.board.editors[index]
        guard stage.needsCloudKit, cloud.devices.indices.contains(index) else { return set }
        let device = cloud.devices[index]
        switch device.connection {
        case .closed: return set == .idle ? .idle : set
        case .offline: return set == .editing ? .editing : .offline
        case .online: break
        }
        let activity = SyncMonitor.shared.activity(for: device.storeIdentifier)
        if activity.exporting { return .sending }
        if activity.importing || activity.settingUp { return .receiving }
        if activity.lastError != nil, set == .idle { return .failed }
        return set
    }
}

/// An editor or device, with a badge for what it's doing.
private struct NodeView: View {
    let symbol: String
    let name: String
    let state: LiveBoard.State

    var body: some View {
        VStack(spacing: 2) {
            Image(systemName: symbol)
                .font(.system(size: 26))
                .foregroundStyle(state == .idle ? Color.primary.opacity(0.7) : state.color)
                .frame(width: 40, height: 34)
                .overlay(alignment: .topTrailing) {
                    if let badge = state.symbol {
                        Image(systemName: badge)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white, state.color)
                            .background(Circle().fill(.background).padding(1))
                            .offset(x: 6, y: -4)
                            .symbolEffect(.bounce, value: state)
                            .symbolEffect(.pulse, isActive: state.isActive)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
            Text(name)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(width: 76)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name): \(String(describing: state))")
    }
}

/// The line between an editor and the hub: arrows that ripple toward the hub while sending and away from it
/// while receiving, a broken line when offline, and a quiet dash otherwise.
private struct LinkView: View {
    let state: LiveBoard.State
    let cloud: Bool

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<3, id: \.self) { _ in
                Rectangle()
                    .fill(lineColor)
                    .frame(height: 2)
            }
            .opacity(state == .offline ? 0.25 : 1)
            Image(systemName: arrow)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(lineColor)
                .symbolEffect(.variableColor.iterative.reversing, isActive: state == .sending || state == .receiving)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 26)
            ForEach(0..<3, id: \.self) { _ in
                Rectangle()
                    .fill(lineColor)
                    .frame(height: 2)
            }
            .opacity(state == .offline ? 0.25 : 1)
        }
        .frame(minWidth: 60, maxWidth: .infinity)
        .accessibilityHidden(true)
    }

    private var arrow: String {
        switch state {
        case .sending: "dot.radiowaves.right"
        case .receiving: "dot.radiowaves.left.and.right"
        case .offline: "wifi.slash"
        case .waiting: "ellipsis"
        case .done: "checkmark"
        default: cloud ? "icloud" : "minus"
        }
    }

    private var lineColor: Color {
        switch state {
        case .sending, .receiving: .blue
        case .offline: .orange
        case .done: .green
        default: Color.secondary.opacity(0.4)
        }
    }
}

/// The store, or iCloud, that every editor or device talks to.
private struct HubView: View {
    let stage: Stage
    let state: LiveBoard.State

    var body: some View {
        VStack(spacing: 2) {
            Image(systemName: symbol)
                .font(.system(size: 34))
                .foregroundStyle(state == .idle ? Color.primary.opacity(0.7) : state.color)
                .symbolEffect(.pulse, isActive: state.isActive)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 54, height: 46)
                .overlay(alignment: .topTrailing) {
                    if let badge = state.symbol {
                        Image(systemName: badge)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white, state.color)
                            .background(Circle().fill(.background).padding(1))
                            .offset(x: 6, y: -4)
                            .symbolEffect(.bounce, value: state)
                    }
                }
            Text(name)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(width: 70)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name): \(String(describing: state))")
    }

    private var symbol: String {
        switch stage {
        case .rules: "arrow.triangle.merge"
        case .oneStoreTwoEditors, .oneStoreThreeEditors: "externaldrive.fill"
        case .twoStores, .threeStores: "icloud.fill"
        }
    }

    private var name: String {
        switch stage {
        case .rules: "Merge"
        case .oneStoreTwoEditors, .oneStoreThreeEditors: "Store"
        case .twoStores, .threeStores: "iCloud"
        }
    }
}
