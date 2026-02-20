// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "harmaline",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "harmaline",
            path: "Sources/Daemon",
            linkerSettings: [
                .linkedFramework("CoreGraphics"),
                .linkedFramework("IOKit"),
            ]
        ),
        .executableTarget(
            name: "HarmalineApp",
            path: "Sources/App",
            linkerSettings: [
                .linkedFramework("SwiftUI"),
            ]
        ),
    ]
)
