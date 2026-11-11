import SwiftUI

struct ContentView: View {
    @Environment(Runner.self) private var runner
    @Environment(CloudLab.self) private var cloud
    @State private var showingSetup = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    PipelineView()
                }
                Section("Now") {
                    LiveDiagramView()
                }
                ForEach(Stage.allCases) { stage in
                    Section {
                        ForEach(runner.tests(in: stage)) { test in
                            NavigationLink(value: test) {
                                TestRow(test: test)
                            }
                        }
                    } header: {
                        StageHeader(stage: stage, run: { runner.run(runner.tests(in: stage)) }, disabled: runner.isRunning)
                    } footer: {
                        if stage.needsCloudKit, !cloud.isConfigured {
                            Label("Needs CloudKit set up: tap the cloud button.", systemImage: "exclamationmark.icloud")
                        }
                    }
                }
            }
            .navigationTitle("Sync Lab")
            .navigationDestination(for: LabTest.self) { test in
                TestDetailView(test: test)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("CloudKit", systemImage: cloud.isConfigured ? "icloud" : "exclamationmark.icloud") {
                        showingSetup = true
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if runner.isRunning {
                        Button("Stop", systemImage: "stop.fill") { runner.stop() }
                    } else {
                        Button("Run all", systemImage: "play.fill") { runner.run(runner.tests) }
                    }
                }
            }
            .sheet(isPresented: $showingSetup) {
                CloudSetupView()
            }
        }
    }
}

/// The CloudKit container, each device's store and sync state, and a way to start over.
struct CloudSetupView: View {
    @Environment(CloudLab.self) private var cloud
    @Environment(Runner.self) private var runner
    @Environment(\.dismiss) private var dismiss
    @State private var erasing = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("Container", value: cloud.containerIdentifier.isEmpty ? "None" : cloud.containerIdentifier)
                    if !cloud.isConfigured {
                        Text("Set SYNCLAB_BUNDLE_ID, SYNCLAB_TEAM and SYNCLAB_CLOUDKIT_CONTAINER in Config.xcconfig, then run on a device or simulator signed in to iCloud.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    if let reason = cloud.unavailableReason {
                        Label(reason, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                            .font(.footnote)
                    }
                } header: {
                    Text("CloudKit")
                }

                Section("Devices") {
                    ForEach(cloud.devices) { device in
                        DeviceRow(device: device)
                    }
                }

                Section {
                    Button(role: .destructive) {
                        erasing = true
                        Task {
                            await cloud.eraseEverything()
                            erasing = false
                        }
                    } label: {
                        if erasing {
                            Label("Erasing…", systemImage: "hourglass")
                        } else {
                            Label("Erase devices and cloud data", systemImage: "trash")
                        }
                    }
                    .disabled(erasing || runner.isRunning)
                } footer: {
                    Text("Deletes every test item from iCloud by way of device A, then each device's store file.")
                }
            }
            .navigationTitle("CloudKit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                Button("Done") { dismiss() }
            }
        }
    }
}

private struct DeviceRow: View {
    let device: Device

    var body: some View {
        let activity = SyncMonitor.shared.activity(for: device.storeIdentifier)
        HStack {
            Image(systemName: "iphone")
            Text("Device \(device.name)")
            Spacer()
            Image(systemName: symbol(activity))
                .foregroundStyle(color(activity))
                .symbolEffect(.pulse, isActive: activity.importing || activity.exporting || activity.settingUp)
                .contentTransition(.symbolEffect(.replace))
            Text(label(activity))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func symbol(_ activity: SyncMonitor.Activity) -> String {
        switch device.connection {
        case .closed: return "moon.zzz"
        case .offline: return "icloud.slash"
        case .online:
            if activity.exporting { return "icloud.and.arrow.up" }
            if activity.importing || activity.settingUp { return "icloud.and.arrow.down" }
            return activity.lastError == nil ? "checkmark.icloud" : "exclamationmark.icloud"
        }
    }

    private func color(_ activity: SyncMonitor.Activity) -> Color {
        switch device.connection {
        case .closed: .secondary
        case .offline: .orange
        case .online: activity.lastError == nil ? .blue : .red
        }
    }

    private func label(_ activity: SyncMonitor.Activity) -> String {
        switch device.connection {
        case .closed: return "Closed"
        case .offline: return "Offline"
        case .online:
            if activity.exporting { return "Sending" }
            if activity.importing || activity.settingUp { return "Receiving" }
            return activity.lastError ?? "Online"
        }
    }
}
