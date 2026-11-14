// swift-tools-version: 6.0
import Foundation
import PackageDescription

/// The download (DMG) build updates itself with Sparkle; `mise run app` sets this with `SPARKLE=1`.
/// The Homebrew build leaves it out: Homebrew owns those files, and the formula builds without
/// fetching any package.
let sparkle = ProcessInfo.processInfo.environment["BROWSERDOOR_SPARKLE"] == "1"

let package = Package(
    name: "Browserdoor",
    platforms: [.macOS(.v14)],
    dependencies: sparkle
        ? [.package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.1")]
        : [],
    targets: [
        .target(name: "BrowserdoorCore"),
        .executableTarget(
            name: "Browserdoor",
            dependencies: ["BrowserdoorCore"] + (sparkle ? [.product(name: "Sparkle", package: "Sparkle")] : []),
            swiftSettings: sparkle ? [.define("SPARKLE")] : []
        ),
        .testTarget(
            name: "BrowserdoorCoreTests",
            dependencies: ["BrowserdoorCore"]
        ),
    ]
)
