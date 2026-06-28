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
        .executableTarget(
            name: "FlowBridgeSharedCheck",
            dependencies: ["FlowBridgeShared"],
            path: "Checks/FlowBridgeSharedCheck"
        )
    ]
)
