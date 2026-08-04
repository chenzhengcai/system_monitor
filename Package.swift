// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SystemMonitor",
    platforms: [.macOS(.v14)],
    targets: [
        // C 桥接层：mach / libproc / statvfs / getifaddrs / getmntinfo
        .target(
            name: "SystemStatsC",
            path: "Sources/SystemStatsC",
            publicHeadersPath: "include"
        ),
        // Swift 可执行：UI + 采集调度
        .executableTarget(
            name: "SystemMonitor",
            dependencies: ["SystemStatsC"],
            path: "Sources/SystemMonitor",
            linkerSettings: [.linkedFramework("ServiceManagement")]
        ),
    ]
)
