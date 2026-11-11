// swift-tools-version: 6.1

import CompilerPluginSupport
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
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-syntax.git", "600.0.0"..<"603.0.0"),
    ],
    targets: [
        .target(name: "Merging", exclude: ["Strategies/README.md"]),
        .macro(name: "MergingMacros", dependencies: [
            .product(name: "SwiftSyntax", package: "swift-syntax"),
            .product(name: "SwiftSyntaxBuilder", package: "swift-syntax"),
            .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
            .product(name: "SwiftDiagnostics", package: "swift-syntax"),
            .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
        ]),
        .target(name: "MergingSwiftData", dependencies: ["Merging", "MergingMacros"]),
        .testTarget(name: "MergingTests", dependencies: ["Merging"]),
        .testTarget(name: "MergingSwiftDataTests", dependencies: ["MergingSwiftData", "Merging"]),
    ]
)
