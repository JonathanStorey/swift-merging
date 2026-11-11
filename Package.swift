// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "swift-merging",
    // Swift 6.1 (Xcode 16.3) or later, for typed throws and Swift Testing.
    platforms: [.iOS(.v17), .macOS(.v14), .tvOS(.v17), .watchOS(.v10), .visionOS(.v1)],
    products: [
        .library(name: "Merging", targets: ["Merging"]),
        // SwiftData models that merge property by property, from the store's history. Empty where SwiftData
        // isn't available, such as Linux.
        .library(name: "MergingSwiftData", targets: ["MergingSwiftData"]),
    ],
    targets: [
        .target(name: "Merging", exclude: ["Strategies/README.md"]),
        .target(name: "MergingSwiftData", dependencies: ["Merging"]),
        .testTarget(name: "MergingTests", dependencies: ["Merging"]),
        .testTarget(name: "MergingSwiftDataTests", dependencies: ["MergingSwiftData", "Merging"]),
    ]
)
