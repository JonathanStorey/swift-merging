#if canImport(SwiftData)
import CloudKit
import CoreData
import Foundation

/// Values read from the sync service's copy of an object, as `StoreChangeCapture.plain` would give them.
struct RemoteValues: @unchecked Sendable {
    var values: [String: Any]
}

/// Where a merge reads what the sync service holds for an object, when the store kept only this device's
/// value. CloudKit's importer does that for any attribute this device edited and hasn't yet exported: it
/// keeps this device's value and drops the other device's, so the two never meet in the store.
protocol RemoteRecordSource: Sendable {
    /// The service's values of `keys` for the object with this Core Data URI, or `nil` if it can't tell.
    func values(forObject object: String, keys: [String]) async throws -> RemoteValues?
}

/// Reads an object's record from CloudKit's private database, the one SwiftData syncs to. It only asks for
/// a record CloudKit has already mentioned in a save of its own, so a store that doesn't sync never calls
/// CloudKit.
struct CloudKitRecordSource: RemoteRecordSource {
    let capture: StoreChangeCapture
    /// The container in the model configuration, or `nil` for the app's default one.
    let containerIdentifier: String?

    func values(forObject object: String, keys: [String]) async throws -> RemoteValues? {
        guard let recordID = capture.recordID(forObject: object) else { return nil }
        let container = containerIdentifier.map { CKContainer(identifier: $0) } ?? CKContainer.default()
        let record = try await container.privateCloudDatabase.record(for: recordID)
        var values: [String: Any] = [:]
        for key in keys {
            // NSPersistentCloudKitContainer names each attribute's field `CD_` and the attribute's name.
            if let value = record["CD_" + key] {
                values[key] = StoreChangeCapture.plain(value)
            }
        }
        return RemoteValues(values: values)
    }
}

/// The names CloudKit's mirroring gives its own contexts, read from Core Data where it exports them, so a
/// renamed constant follows along.
enum CloudKitNames {
    /// The author of CloudKit's import saves.
    static let importAuthor = exported("NSCloudKitMirroringDelegateImportContextName") ?? "NSCloudKitMirroringDelegate.import"
    /// The author of the save that records a finished export.
    static let exportAuthor = exported("NSCloudKitMirroringDelegateExportContextName") ?? "NSCloudKitMirroringDelegate.export"

    /// A string constant Core Data exports, or `nil` if it doesn't.
    static func exported(_ symbol: String) -> String? {
        // RTLD_DEFAULT: every image loaded, which Swift doesn't import as a constant.
        guard let address = dlsym(UnsafeMutableRawPointer(bitPattern: -2), symbol) else { return nil }
        let string = address.assumingMemoryBound(to: Unmanaged<NSString>?.self).pointee
        return string?.takeUnretainedValue() as String?
    }
}
#endif
