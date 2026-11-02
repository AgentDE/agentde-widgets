// swift-tools-version:5.10
import PackageDescription

// AgentDE's sidebar widget spot, its menu, the Calendar widget and JSON plugins' widgets. Other extensions add
// widgets by conforming to `WidgetProvider`.
let package = Package(
    name: "agentde-widgets",
    platforms: [.macOS(.v14)],
    products: [.library(name: "AgentDEWidgets", targets: ["AgentDEWidgets"])],
    dependencies: [.package(path: "../agentde")],
    targets: [
        .target(name: "AgentDEWidgets", dependencies: [.product(name: "AgentDEKit", package: "agentde")], path: "Sources/AgentDEWidgets"),
        .testTarget(name: "AgentDEWidgetsTests", dependencies: ["AgentDEWidgets", .product(name: "AgentDE", package: "agentde")],
                    path: "Tests/AgentDEWidgetsTests"),
    ]
)
