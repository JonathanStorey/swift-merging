// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "AppleProbe",
    platforms: [.macOS(.v15)],
    targets: [.executableTarget(name: "AppleProbe", swiftSettings: [.swiftLanguageMode(.v5)])]
)
