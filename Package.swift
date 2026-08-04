// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "FlowBridge",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "FlowBridgeShared",
            targets: ["FlowBridgeShared"]
        ),
        .executable(
            name: "FlowBridgeSharedCheck",
            targets: ["FlowBridgeSharedCheck"]
        )
    ],
    targets: [
        .target(
            name: "FlowBridgeShared",
            path: "Sources/FlowBridgeShared"
        ),
        // Galleria visiva del design system su macOS: si guarda, non si spedisce.
        .executableTarget(
            name: "AnteprimaMac",
            dependencies: ["FlowBridgeShared"],
            path: "Sources/AnteprimaMac"
        ),
        .executableTarget(
            name: "FlowBridgeSharedCheck",
            dependencies: ["FlowBridgeShared"],
            path: "Checks/FlowBridgeSharedCheck"
        ),
        // Lets the XCTest suite for the shared framework run on Linux CI
        // (`swift test`), independent of the iOS `bundle.unit-test` target
        // in project.yml that Xcode builds.
        .testTarget(
            name: "FlowBridgeSharedTests",
            dependencies: ["FlowBridgeShared"],
            path: "Tests/FlowBridgeSharedTests"
        )
    ]
)
