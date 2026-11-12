// swift-tools-version: 5.9
import PackageDescription

// `#file` expands to "Module/File.swift" instead of an absolute path, so built binaries never
// embed the build machine's directory layout (or its username) in assertion messages.
let shortPaths: [SwiftSetting] = [.enableUpcomingFeature("ConciseMagicFile")]

let package = Package(
    name: "Vigil",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "vigil", targets: ["vigil"]),
        .executable(name: "VigilApp", targets: ["VigilApp"]),
    ],
    targets: [
        // Pure logic: no IOKit, no AppKit, no I/O. Everything here is unit-tested.
        .target(name: "VigilCore", path: "Sources/VigilCore", swiftSettings: shortPaths),
        // Thin adapters over macOS APIs (IOKit, libproc, /usr/bin/top). No network.
        .target(name: "VigilSystem", dependencies: ["VigilCore"], path: "Sources/VigilSystem", swiftSettings: shortPaths),
        // The command-line tool: a thin wrapper over the two libraries above.
        .executableTarget(name: "vigil", dependencies: ["VigilCore", "VigilSystem"], path: "Sources/vigil", swiftSettings: shortPaths),
        // The menu-bar app (SwiftUI). Wrapped into Vigil.app by scripts/build-app.sh.
        .executableTarget(name: "VigilApp", dependencies: ["VigilCore", "VigilSystem"], path: "Sources/VigilApp", swiftSettings: shortPaths),
        .testTarget(name: "VigilCoreTests", dependencies: ["VigilCore"], path: "Tests/VigilCoreTests"),
        .testTarget(name: "VigilSystemTests", dependencies: ["VigilSystem", "VigilCore"], path: "Tests/VigilSystemTests"),
    ]
)
