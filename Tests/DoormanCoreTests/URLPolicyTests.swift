import Foundation
import Testing
@testable import DoormanCore

struct URLPolicyTests {
    @Test(arguments: [
        "https://example.com", "http://example.com/a?b=c", "HTTPS://EXAMPLE.COM", "file:///Users/x/page.html",
    ])
    func allows(_ string: String) throws {
        #expect(URLPolicy.isAllowed(try #require(URL(string: string))))
    }

    @Test(arguments: [
        "--remote-debugging-port=9222", "-foo", "javascript:alert(1)", "data:text/html,hi",
        "mailto:a@b.c", "ftp://example.com", "zen://space", "relative/path",
    ])
    func rejects(_ string: String) throws {
        #expect(!URLPolicy.isAllowed(try #require(URL(string: string))))
    }
}
