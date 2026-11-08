@testable import DoormanCore
import Foundation
import Testing

struct URLPolicyTests {
    @Test(arguments: [
        "https://example.com", "http://example.com/a?b=c", "HTTPS://EXAMPLE.COM", "file:///Users/x/page.html",
    ])
    func allows(_ string: String) throws {
        #expect(try URLPolicy.isAllowed(#require(URL(string: string))))
    }

    @Test(arguments: [
        "--remote-debugging-port=9222", "-foo", "javascript:alert(1)", "data:text/html,hi",
        "mailto:a@b.c", "ftp://example.com", "zen://space", "relative/path",
    ])
    func rejects(_ string: String) throws {
        #expect(try !URLPolicy.isAllowed(#require(URL(string: string))))
    }

    @Test func weblocIsWebOnly() throws {
        #expect(try URLPolicy.isAllowedFromWebloc(#require(URL(string: "https://example.com"))))
        #expect(try URLPolicy.isAllowedFromWebloc(#require(URL(string: "http://example.com"))))
        #expect(try !URLPolicy.isAllowedFromWebloc(#require(URL(string: "file:///Users/x/Downloads/x.html"))))
        #expect(try !URLPolicy.isAllowedFromWebloc(#require(URL(string: "--flag"))))
    }
}
