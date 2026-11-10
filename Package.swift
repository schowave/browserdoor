// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Browserdoor",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "BrowserdoorCore"),
        .executableTarget(name: "Browserdoor", dependencies: ["BrowserdoorCore"]),
        .testTarget(
            name: "BrowserdoorCoreTests",
            dependencies: ["BrowserdoorCore"]
        ),
    ]
)
