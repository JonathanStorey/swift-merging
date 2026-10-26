// swift-tools-version: 6.0

import CompilerPluginSupport
import PackageDescription

let package = Package(
    name: "swift-merging",
    // Swift 6 for typed throws and Swift Testing, and the OS releases that ship with it.
    platforms: [.iOS(.v17), .macOS(.v14), .tvOS(.v17), .watchOS(.v10), .visionOS(.v1)],
    products: [
        .library(name: "Merging", targets: ["Merging"]),
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-syntax.git", "600.0.0"..<"603.0.0"),
    ],
    targets: [
        .macro(
            name: "MergingMacros",
            dependencies: [
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
            ]
        ),
        .target(
            name: "Merging",
            dependencies: ["MergingMacros"]
        ),
        .testTarget(
            name: "MergingTests",
            dependencies: ["Merging"]
        ),
        // Expansion tests run under Swift Testing through swift-syntax's framework-neutral test support.
        .testTarget(
            name: "MergingMacrosTests",
            dependencies: [
                "MergingMacros",
                .product(name: "SwiftSyntaxMacrosGenericTestSupport", package: "swift-syntax"),
            ]
        ),
    ]
)
