@testable import BrowserdoorCore
import Foundation
import Testing

/// Records what `LinkOpener` asks of the system.
final class RecordingPort: LaunchPort {
    enum Call: Equatable {
        case run(String, [String])
        case open([String], String)
        case activate(String)
    }

    var running: Set<String> = []
    var files: [String: Data] = [:]
    private(set) var calls: [Call] = []

    func isRunning(app: URL) -> Bool {
        running.contains(app.path)
    }

    func contents(of file: URL) -> Data? {
        files[file.path]
    }

    func run(_ executable: URL, arguments: [String]) {
        calls.append(.run(executable.path, arguments))
    }

    func open(_ urls: [URL], with app: URL) {
        calls.append(.open(urls.map(\.absoluteString), app.path))
    }

    func activate(_ app: URL) {
        calls.append(.activate(app.path))
    }
}

struct LinkOpenerTests {
    let zenApp = URL(fileURLWithPath: "/Applications/Zen.app")
    let zenExe = URL(fileURLWithPath: "/Applications/Zen.app/Contents/MacOS/zen")
    let chrome = URL(fileURLWithPath: "/Applications/Google Chrome.app")
    let safari = URL(fileURLWithPath: "/Applications/Safari.app")
    let a = URL(string: "https://a.example")!
    let b = URL(string: "https://b.example/x?y=1")!

    func port() -> RecordingPort {
        RecordingPort()
    }

    func zenSpace(profile: URL? = nil) -> Target {
        Target(id: "zen:{u}", name: "U",
               kind: .zenSpace(app: zenApp, executable: zenExe, space: ZenSpace(uuid: "{u}", name: "U"), profile: profile))
    }

    func webloc(_ url: String) throws -> Data {
        try PropertyListSerialization.data(fromPropertyList: ["URL": url], format: .xml, options: 0)
    }

    // MARK: Incoming items

    @Test func passesWebAndFileLinks() {
        let file = URL(fileURLWithPath: "/Users/x/page.html")
        #expect(LinkOpener(port: port()).links(from: [a, file]) == [a, file])
    }

    @Test(arguments: ["javascript:alert(1)", "data:text/html,hi", "mailto:a@b.c", "ftp://x", "zen://space", "--flag", "-x"])
    func dropsEverythingElse(_ string: String) throws {
        #expect(try LinkOpener(port: port()).links(from: [#require(URL(string: string))]).isEmpty)
    }

    @Test func resolvesWeblocToWebLinksOnly() throws {
        let port = port()
        port.files["/d/ok.webloc"] = try webloc("https://example.com/a")
        port.files["/d/local.webloc"] = try webloc("file:///Users/x/Downloads/x.html")
        port.files["/d/flag.webloc"] = try webloc("--remote-debugging-port=9222")
        port.files["/d/garbage.webloc"] = Data("nope".utf8)
        let items = ["ok", "local", "flag", "garbage", "missing"].map { URL(fileURLWithPath: "/d/\($0).webloc") }
        #expect(try LinkOpener(port: port).links(from: items) == [#require(URL(string: "https://example.com/a"))])
    }

    // MARK: Opening

    @Test func runningZenGetsOneRemoteCommandPerLinkThenActivates() {
        let port = port()
        port.running = [zenApp.path]
        LinkOpener(port: port).open([a, b], in: zenSpace())
        #expect(port.calls == [
            .run(zenExe.path, ["--space", "{u}", a.absoluteString]),
            .run(zenExe.path, ["--space", "{u}", b.absoluteString]),
            .activate(zenApp.path),
        ])
    }

    @Test func closedZenStartsThroughLaunchServicesWithoutActivate() {
        let port = port()
        LinkOpener(port: port).open([a, b], in: zenSpace())
        #expect(port.calls == [
            .run("/usr/bin/open", ["-a", zenApp.path, "--args", "--space", "{u}", a.absoluteString, b.absoluteString]),
        ])
    }

    @Test func zenProfileOverrideIsPassed() {
        let port = port()
        port.running = [zenApp.path]
        LinkOpener(port: port).open([a], in: zenSpace(profile: URL(fileURLWithPath: "/p/work")))
        #expect(port.calls.first == .run(zenExe.path, ["--profile", "/p/work", "--space", "{u}", a.absoluteString]))
    }

    @Test func chromiumOpensWithProfileDirectory() {
        let port = port()
        let target = Target(id: "c", name: "C", kind: .chromium(app: chrome, profileDirectory: "Profile 2"))
        LinkOpener(port: port).open([a, b], in: target)
        #expect(port.calls == [
            .run("/usr/bin/open", ["-na", chrome.path, "--args", "--profile-directory=Profile 2", a.absoluteString, b.absoluteString]),
        ])
    }

    @Test func plainBrowserGoesThroughLaunchServices() {
        let port = port()
        LinkOpener(port: port).open([a, b], in: Target(id: "s", name: "Safari", kind: .app(safari)))
        #expect(port.calls == [.open([a.absoluteString, b.absoluteString], safari.path)])
    }

    @Test func disallowedLinksNeverReachACommandLine() throws {
        let port = port()
        port.running = [zenApp.path]
        let evil = try [#require(URL(string: "--load-extension=/tmp/x")), #require(URL(string: "javascript:alert(1)"))]
        LinkOpener(port: port).open(evil, in: zenSpace())
        LinkOpener(port: port).open(evil, in: Target(id: "c", name: "C", kind: .chromium(app: chrome, profileDirectory: "Default")))
        #expect(port.calls.isEmpty)
    }
}

struct ClipboardLinkTests {
    @Test func findsURLsInText() {
        let urls = LinkOpener.urls(inText: "https://a.example\n  see https://b.example/x?y=1 and words\tjavascript:alert(1)")
        #expect(urls.map(\.absoluteString) == ["https://a.example", "https://b.example/x?y=1", "javascript:alert(1)"])
        #expect(URLPolicy.filter(urls).count == 2)
        #expect(LinkOpener.urls(inText: "no links here").isEmpty)
    }

    @Test func issueReportPrefillsVersionsOnly() {
        let url = IssueReport.url(appVersion: "0.6.0", macOSVersion: "15.4.1")
        #expect(url.absoluteString
            == "https://github.com/schowave/browserdoor/issues/new?template=bug.yml&versions=Browserdoor%200.6.0,%20macOS%2015.4.1")
    }
}
