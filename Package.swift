// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Doorman",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "DoormanCore"),
        .executableTarget(name: "Doorman", dependencies: ["DoormanCore"]),
        .testTarget(
            name: "DoormanCoreTests",
            dependencies: ["DoormanCore"]
        ),
    ]
)
