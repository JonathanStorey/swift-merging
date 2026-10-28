// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "swift-merging",
    // Swift 6.1 (Xcode 16.3) or later, for typed throws and Swift Testing.
    platforms: [.iOS(.v17), .macOS(.v14), .tvOS(.v17), .watchOS(.v10), .visionOS(.v1)],
    products: [
        .library(name: "Merging", targets: ["Merging"]),
    ],
    targets: [
        .target(name: "Merging", exclude: ["Strategies/README.md"]),
        .testTarget(name: "MergingTests", dependencies: ["Merging"]),
    ]
)
