import CloudKit
import Foundation
import Observation
import SwiftData

/// Two or three stores in this one app, each syncing to the same CloudKit container and zone, standing in
/// for devices. What they share that real devices don't is this process and its pushes, so a push can wake
/// them together; the timings, and reopening one store at a time, keep that from hiding problems.
@MainActor @Observable
final class CloudLab {
    static let shared = CloudLab()

    /// The CloudKit container, from Config.xcconfig by way of Info.plist.
    let containerIdentifier: String
    let devices: [Device]
    /// Why the CloudKit stages can't run, once checked, or `nil` while they can.
    private(set) var unavailableReason: String?
    @ObservationIgnored private var checkedAccount = false
    /// The running test's log, for CloudKit's events.
    @ObservationIgnored private var currentLab: LabContext?

    static let placeholderContainer = "iCloud.com.example.SyncLab"

    init() {
        containerIdentifier = (Bundle.main.object(forInfoDictionaryKey: "SyncLabCloudKitContainer") as? String) ?? ""
        let root = URL.applicationSupportDirectory.appending(path: "SyncLab", directoryHint: .isDirectory)
        devices = Device.names.map { Device(name: $0, root: root) }
        SyncMonitor.shared.onEvent = { [weak self] store, line in
            guard let self, let lab = self.currentLab, let device = self.devices.first(where: { $0.storeIdentifier == store }) else { return }
            lab.log("☁︎ \(device.name): \(line)")
        }
    }

    var isConfigured: Bool {
        !containerIdentifier.isEmpty && containerIdentifier != Self.placeholderContainer && !containerIdentifier.hasPrefix("$(")
    }

    /// Throws `LabSkip` unless CloudKit is set up and signed in.
    func ensureAvailable() async throws {
        guard isConfigured else {
            unavailableReason = "Set SYNCLAB_CLOUDKIT_CONTAINER, SYNCLAB_BUNDLE_ID and SYNCLAB_TEAM in Config.xcconfig to run the CloudKit stages."
            throw LabSkip(reason: unavailableReason!)
        }
        if !checkedAccount {
            let status = try await CKContainer(identifier: containerIdentifier).accountStatus()
            guard status == .available else {
                unavailableReason = "iCloud isn't available (account status \(status.rawValue)). Sign in to iCloud on this device or simulator."
                throw LabSkip(reason: unavailableReason!)
            }
            checkedAccount = true
            unavailableReason = nil
        }
    }

    // MARK: - A test

    func run(_ kind: DataKind, timing: Timing, devices count: Int, _ lab: LabContext) async throws -> [String] {
        try await ensureAvailable()
        currentLab = lab
        defer { currentLab = nil }
        let devices = Array(self.devices.prefix(count))
        try await prepare(devices, lab)
        let a = devices[0]
        let others = Array(devices.dropFirst())
        let key = UUID().uuidString

        // A creates the item, and every device gets it.
        let main = try a.mainContext()
        let item = Item(key: key)
        main.insert(item)
        Scenario.seed(item, in: main)
        lab.board.set(0, .sending)
        try main.save()
        lab.log("A created the item")
        try await waitUntil("every device has the item", nudging: others, lab) {
            try devices.allSatisfy { try $0.storedValues(key) == ItemValues.base }
        }
        defer { cleanUp(key, on: a, lab) }
        lab.board.setAll(.idle)

        // Each device makes its edit, at the test's timing.
        lab.log("Timing: \(timing.title)")
        switch timing {
        case .together:
            for (index, device) in devices.enumerated() {
                try device.edit(key, kind, by: index)
                lab.board.set(index, .editing)
            }
            try await pause()
            for (index, device) in devices.enumerated() {
                try device.save()
                lab.board.set(index, .sending)
            }
            lab.log("Every device saved its edit at the same moment")

        case .whileEditing:
            for (index, device) in devices.enumerated().dropFirst() {
                try device.edit(key, kind, by: index)
                lab.board.set(index, .editing)
                lab.log("\(device.name) \(kind.editSummary(index)), and doesn't save yet")
            }
            try a.edit(key, kind, by: 0)
            try a.save()
            lab.board.set(0, .sending)
            lab.log("A \(kind.editSummary(0)), and saves")
            // No nudging here: reopening a device would drop its unsaved edit, so this waits on CloudKit's push.
            try await waitUntil("\(names(others)) receive A's edit", timeout: .seconds(150), lab) {
                try others.allSatisfy { try kind.reflects($0.storedValues(key), editor: 0) }
            }
            for (offset, device) in others.enumerated() {
                lab.board.set(offset + 1, .sending)
                try device.save()
                lab.log("\(device.name) saves, merging A's edit into its own first")
            }

        case .offline:
            for (offset, device) in others.enumerated() {
                try await device.reopen(online: false, cloudKitContainer: containerIdentifier)
                lab.board.set(offset + 1, .offline)
                try device.edit(key, kind, by: offset + 1)
                try device.save()
                lab.log("\(device.name) went offline, \(kind.editSummary(offset + 1)), and saved")
            }
            let saved = Date.now
            try a.edit(key, kind, by: 0)
            try a.save()
            lab.board.set(0, .sending)
            lab.log("A \(kind.editSummary(0)), and saves")
            try await waitUntil("A exports its edit", timeout: .seconds(90), lab) {
                SyncMonitor.shared.exported(a.storeIdentifier, since: saved)
            }
            lab.board.set(0, .done)
            // One at a time, so each reconnection meets what the earlier ones sent.
            for (offset, device) in others.enumerated() {
                let reopened = Date.now
                try await device.reopen(online: true, cloudKitContainer: containerIdentifier)
                lab.board.set(offset + 1, .receiving)
                lab.log("\(device.name) is back online")
                do {
                    try await waitUntil("\(device.name) finishes an import", timeout: .seconds(60), lab) {
                        SyncMonitor.shared.imported(device.storeIdentifier, since: reopened)
                    }
                } catch let error as LabError {
                    lab.log("Going on anyway: \(error.message)")
                }
            }
        }

        // Every device ends up with every edit, and with the same values.
        let want = kind.expected(editors: count)
        var last: [ItemValues?] = []
        do {
            try await waitUntil("every device holds every edit", nudging: devices, lab) {
                last = try devices.map { try $0.storedValues(key) }
                return last.allSatisfy { $0.map { kind.mismatches($0, editors: count).isEmpty } ?? false }
                    && Set(last.map { $0?.steps ?? [] }).count == 1
            }
        } catch let error as LabError {
            lab.log(error.message)
        }
        var failures: [String] = []
        for (device, values) in zip(devices, last) {
            guard let values else {
                failures.append("\(device.name) lost the item")
                continue
            }
            lab.log("\(device.name) holds \(values.summary)")
            failures += kind.mismatches(values, editors: count).map { "\(device.name): \($0)" }
        }
        if failures.isEmpty, Set(last.compactMap { $0?.steps }).count > 1 {
            failures.append("The devices ordered the steps differently: \(last.compactMap { $0?.steps })")
        }
        if failures.isEmpty { lab.log("Every device holds \(want.summary)") }
        return failures
    }

    // MARK: - Devices

    /// Opens `devices` online, closes the rest, and lets each finish its first import.
    private func prepare(_ devices: [Device], _ lab: LabContext) async throws {
        for device in self.devices where !devices.contains(where: { $0 === device }) && device.connection != .closed {
            device.close()
        }
        for (index, device) in devices.enumerated() where device.connection != .online {
            let opened = Date.now
            try await device.reopen(online: true, cloudKitContainer: containerIdentifier)
            lab.board.set(index, .receiving)
            lab.log("Opened device \(device.name)")
            do {
                try await waitUntil("\(device.name) finishes its first import", timeout: .seconds(60), lab) {
                    SyncMonitor.shared.imported(device.storeIdentifier, since: opened)
                }
            } catch let error as LabError {
                lab.log("Going on anyway: \(error.message)")
            }
            lab.board.set(index, .idle)
        }
    }

    /// Deletes the test's item and its labels from device A, which syncs the deletion to the others.
    private func cleanUp(_ key: String, on device: Device, _ lab: LabContext) {
        do {
            if device.connection != .online { return }
            let main = try device.mainContext()
            main.rollback()
            if let item = try Scenario.item(key, in: main) {
                for label in item.labels ?? [] { main.delete(label) }
                main.delete(item)
                try main.save()
            }
        } catch {
            lab.log("Couldn't clean up: \(error.localizedDescription)")
        }
    }

    /// Deletes every item and label from CloudKit by way of device A, then every device's local files.
    func eraseEverything() async {
        guard isConfigured else {
            for device in devices { device.erase() }
            return
        }
        do {
            let a = devices[0]
            try await a.reopen(online: true, cloudKitContainer: containerIdentifier)
            let main = try a.mainContext()
            try await Task.sleep(for: .seconds(5))
            for item in try main.fetch(FetchDescriptor<Item>()) { main.delete(item) }
            for label in try main.fetch(FetchDescriptor<Tag>()) { main.delete(label) }
            let saved = Date.now
            try main.save()
            let clock = ContinuousClock()
            let deadline = clock.now + .seconds(60)
            while clock.now < deadline, !SyncMonitor.shared.exported(a.storeIdentifier, since: saved) {
                try await Task.sleep(for: .seconds(1))
            }
        } catch {}
        for device in devices { device.erase() }
        checkedAccount = false
    }

    // MARK: - Waiting

    /// Checks `condition` every second until it holds. Every 30 seconds it reopens the devices in `nudging`,
    /// which makes CloudKit import at once instead of waiting for a push.
    private func waitUntil(_ description: String, timeout: Duration = .seconds(180), nudging: [Device] = [], _ lab: LabContext,
                           _ condition: () throws -> Bool) async throws {
        let clock = ContinuousClock()
        let start = clock.now
        var lastNudge = start
        lab.board.wait(for: description)
        lab.board.hub = .waiting
        defer {
            lab.board.wait(for: nil)
            lab.board.hub = .idle
        }
        while true {
            try Task.checkCancellation()
            if try condition() {
                lab.log("✓ \(description) (\((clock.now - start).components.seconds)s)")
                return
            }
            if clock.now - start > timeout {
                throw LabError("Timed out after \(timeout.components.seconds)s waiting until \(description)")
            }
            if !nudging.isEmpty, clock.now - lastNudge > .seconds(30) {
                for device in nudging where device.connection == .online {
                    lab.log("Reopening \(device.name) to make it import now")
                    try await device.reopen(online: true, cloudKitContainer: containerIdentifier)
                }
                lastNudge = clock.now
            }
            try await Task.sleep(for: .seconds(1))
        }
    }

    private func pause() async throws {
        try await Task.sleep(for: .milliseconds(300))
    }

    private func names(_ devices: [Device]) -> String {
        devices.map(\.name).joined(separator: " and ")
    }
}

extension ItemValues {
    static let base = Draft().values
}
