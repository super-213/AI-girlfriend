// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "KanbanAgentSDK",
    platforms: [.macOS(.v15), .iOS(.v18)],
    products: [
        .library(name: "KanbanAgentSDK", targets: ["KanbanAgentSDK"])
    ],
    targets: [
        .target(name: "KanbanAgentSDK"),
        .testTarget(name: "KanbanAgentSDKTests", dependencies: ["KanbanAgentSDK"])
    ]
)
