@testable import BrowserdoorCore
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

/// A machine with Zen (3 spaces), Chrome (2 profiles), Chrome Beta, Firefox, Safari and some
/// non-browsers, used by discovery and catalog tests.
func sampleEnvironment(zenVersion: String = "1.24.1b") -> FakeEnvironment {
    var env = FakeEnvironment()
    env.addApp("io.github.schowave.doorman", name: "Browserdoor")
    env.addApp("com.apple.Safari", name: "Safari")
    env.addApp("app.zen-browser.zen", name: "Zen", version: zenVersion, executable: "zen")
    env.addApp("com.google.Chrome", name: "Google Chrome")
    env.addApp("com.google.Chrome.beta", name: "Google Chrome Beta")
    env.addApp("org.mozilla.firefox", name: "Firefox")
    env.addApp("com.googlecode.iterm2", name: "iTerm")
    env.addApp("se.johnste.finicky", name: "Finicky")
    env.addApp("com.webcatalog.juli.gmail", name: "Gmail", folder: "/Users/test/Applications/WebCatalog Apps")
    // A test browser in a cache dir, registered before the real Chrome.
    let cached = URL(fileURLWithPath: "/Users/test/.cache/puppeteer/chrome/Google Chrome.app")
    env.extraHandlers = [cached]
    env.extraInfos[cached] = AppInfo(bundleId: "com.google.Chrome", name: "Cached Chrome")

    let zenRoot = "/Users/test/Library/Application Support/zen"
    env.files["\(zenRoot)/profiles.ini"] = Data("[Install1]\nDefault=Profiles/p1\n".utf8)
    env.files["\(zenRoot)/Profiles/p1/zen-sessions.jsonlz4"] = mozLz4(json: sessionJSON)

    let chrome = "/Users/test/Library/Application Support/Google/Chrome/Local State"
    env.files[chrome] = Data(#"{"profile":{"info_cache":{"Default":{"name":"Work"},"Profile 2":{"name":"David"}}}}"#.utf8)
    let beta = "/Users/test/Library/Application Support/Google/Chrome Beta/Local State"
    env.files[beta] = Data(#"{"profile":{"info_cache":{"Default":{"name":"Person 1"}}}}"#.utf8)
    return env
}
