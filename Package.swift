// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "swift-merging",
    // Swift 6.1 (Xcode 16.3) or later, for typed throws and Swift Testing.
    platforms: [.iOS(.v17), .macOS(.v14), .tvOS(.v17), .watchOS(.v10), .visionOS(.v1)],
    products: [
        .library(name: "Merging", targets: ["Merging"]),
        // Sync status for SwiftData with CloudKit: a monitor, each object's status, and waits for uploads.
        // Independent of Merging, and empty where SwiftData isn't available, such as Linux.
        .library(name: "Persistence", targets: ["Persistence"]),
    ],
    targets: [
        .target(name: "Merging", exclude: ["Strategies/README.md"]),
        .target(name: "Persistence"),
        .testTarget(name: "MergingTests", dependencies: ["Merging"]),
        .testTarget(name: "PersistenceTests", dependencies: ["Persistence"]),
    ]
)
