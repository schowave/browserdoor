@testable import BrowserdoorCore
import Foundation
import Testing

struct LinkDisplayTests {
    let home = URL(fileURLWithPath: "/Users/test", isDirectory: true)

    func display(_ string: String) -> LinkDisplay {
        LinkDisplay(URL(string: string)!, home: home)
    }

    @Test func splitsHostFromTheRest() {
        #expect(display("https://github.com/schowave/browserdoor?tab=readme#top")
            == LinkDisplay(primary: "github.com", secondary: "/schowave/browserdoor?tab=readme#top"))
        #expect(display("https://example.com/") == LinkDisplay(primary: "example.com", secondary: ""))
        #expect(display("http://localhost:8080/x") == LinkDisplay(primary: "localhost:8080", secondary: "/x"))
        #expect(display("http://[::1]:80/x").primary == "[::1]:80")
    }

    @Test func showsLookAlikeHostsInPunycode() {
        // Cyrillic "а" in place of the Latin "a".
        #expect(display("https://\u{0430}pple.com/").primary == "xn--pple-43d.com")
        #expect(display("https://äpple.com/").primary == "xn--pple-koa.com")
    }

    @Test func hidesUserInfoThatPosesAsTheHost() {
        #expect(display("https://bank.com@evil.io/login").primary == "evil.io")
    }

    @Test func namesFilesByNameAndFolder() {
        let inHome = LinkDisplay(URL(fileURLWithPath: "/Users/test/Downloads/a b.html"), home: home)
        #expect(inHome == LinkDisplay(primary: "a b.html", secondary: "~/Downloads"))
        let elsewhere = LinkDisplay(URL(fileURLWithPath: "/tmp/page.html"), home: home)
        #expect(elsewhere == LinkDisplay(primary: "page.html", secondary: "/tmp"))
        let similarPrefix = LinkDisplay(URL(fileURLWithPath: "/Users/tester/page.html"), home: home)
        #expect(similarPrefix.secondary == "/Users/tester")
    }
}
