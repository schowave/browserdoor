@testable import DoormanCore
import Foundation

/// Wraps `payload` in a mozLz4 container using a literal-only LZ4 block.
/// Valid LZ4 (one sequence, no match) — good enough to produce fixtures.
func mozLz4(literalOnly payload: [UInt8]) -> Data {
    var out = MozLz4.magic
    let n = payload.count
    out += [UInt8(n & 0xFF), UInt8(n >> 8 & 0xFF), UInt8(n >> 16 & 0xFF), UInt8(n >> 24 & 0xFF)]
    if n < 15 {
        out.append(UInt8(n << 4))
    } else {
        out.append(0xF0)
        var rest = n - 15
        while rest >= 255 {
            out.append(255)
            rest -= 255
        }
        out.append(UInt8(rest))
    }
    out += payload
    return Data(out)
}

func mozLz4(json: String) -> Data {
    mozLz4(literalOnly: Array(json.utf8))
}

struct FakeEnvironment: BrowserEnvironment {
    var home = URL(fileURLWithPath: "/Users/test")
    var ownBundleId = "io.github.schowave.doorman"
    var apps: [String: (url: URL, info: AppInfo)] = [:]
    var handlers: [String] = []
    var files: [String: Data] = [:]

    mutating func addApp(_ bundleId: String, name: String, version: String? = nil, executable: String? = nil, folder: String = "/Applications") {
        let url = URL(fileURLWithPath: "\(folder)/\(name).app")
        apps[bundleId] = (url, AppInfo(bundleId: bundleId, name: name, version: version, executableName: executable))
        handlers.append(bundleId)
    }

    func httpsHandlers() -> [URL] {
        extraHandlers + handlers.compactMap { apps[$0]?.url }
    }

    func appInfo(at app: URL) -> AppInfo? {
        apps.values.first(where: { $0.url == app })?.info ?? extraInfos[app]
            ?? nonBrowserApps.values.first(where: { $0.url == app })?.info
    }

    /// Extra copies of an app registered under the same bundle ID at another path.
    var extraInfos: [URL: AppInfo] = [:]
    var extraHandlers: [URL] = []
    /// Apps LaunchServices knows but that don't handle https.
    var nonBrowserApps: [String: (url: URL, info: AppInfo)] = [:]
    func applicationURL(bundleId: String) -> URL? {
        apps[bundleId]?.url ?? nonBrowserApps[bundleId]?.url
    }

    func contents(of file: URL) -> Data? {
        files[file.path]
    }
}
