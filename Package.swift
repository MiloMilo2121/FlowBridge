// swift-tools-version: 6.0

import PackageDescription

var targets: [Target] = [
    .target(name: "FlowBridgeShared", path: "Sources/FlowBridgeShared"),
    .executableTarget(name: "FlowBridgeSharedCheck", dependencies: ["FlowBridgeShared"],
                      path: "Checks/FlowBridgeSharedCheck"),
    .testTarget(name: "FlowBridgeSharedTests", dependencies: ["FlowBridgeShared"],
                path: "Tests/FlowBridgeSharedTests",
                resources: [.copy("../Fixtures/diario")])
]
#if os(macOS)
// AppKit is unavailable in the Linux CI container.
targets.append(.executableTarget(name: "AnteprimaMac", dependencies: ["FlowBridgeShared"],
                                 path: "Sources/AnteprimaMac"))
#endif

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
    targets: targets
)
