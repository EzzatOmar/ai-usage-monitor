// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "AIUsageMonitor",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "AIUsageMonitor", targets: ["AIUsageMonitor"]),
    ],
    targets: [
        .executableTarget(
            name: "AIUsageMonitor",
            path: "Sources",
            linkerSettings: [
                .linkedLibrary("sqlite3"),
            ]
        ),
        .testTarget(
            name: "AIUsageMonitorTests",
            dependencies: ["AIUsageMonitor"],
            path: "Tests"
        ),
    ]
)
