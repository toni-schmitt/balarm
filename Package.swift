// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "Balarm",
    platforms: [.macOS(.v26)],
    targets: [
        .target(name: "BalarmCore"),
        .executableTarget(
            name: "Balarm",
            dependencies: ["BalarmCore"]
        ),
        .testTarget(
            name: "BalarmCoreTests",
            dependencies: ["BalarmCore"]
        ),
        .testTarget(
            name: "BalarmTests",
            dependencies: ["Balarm"]
        ),
    ]
)
