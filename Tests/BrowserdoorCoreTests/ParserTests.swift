@testable import BrowserdoorCore
import Foundation
import Testing

let sessionJSON = """
{
  "lastCollected": 1,
  "tabs": [],
  "spaces": [
    {"uuid": "{aaaa}", "name": "Work", "icon": "chrome://browser/skin/zen-icons/selectable/briefcase.svg",
     "containerTabId": 6,
     "theme": {"type": "gradient", "gradientColors": [
        {"c": [1, 2, 3], "isPrimary": false},
        {"c": [242, 155, 187], "isPrimary": true}
     ]}},
    {"uuid": "{bbbb}", "name": "Home", "icon": "🏠", "theme": {"gradientColors": []}},
    {"uuid": "{cccc}", "name": "Bare"}
  ]
}
"""

struct ZenSpacesTests {
    @Test func parsesSpaces() throws {
        let spaces = try ZenSpaces.parse(sessionJSON: Data(sessionJSON.utf8))
        #expect(spaces.map(\.name) == ["Work", "Home", "Bare"])
        #expect(spaces[0].uuid == "{aaaa}")
        #expect(spaces[0].color == RGB(242, 155, 187))
        #expect(spaces[0].bundledIconName == "briefcase.svg")
        #expect(spaces[0].emojiIcon == nil)
        #expect(spaces[1].emojiIcon == "🏠")
        #expect(spaces[1].bundledIconName == nil)
        #expect(spaces[1].color == nil)
        #expect(spaces[2].icon == nil)
    }

    @Test func toleratesMissingSpaces() throws {
        #expect(try ZenSpaces.parse(sessionJSON: Data("{\"tabs\":[]}".utf8)).isEmpty)
    }
}

struct ZenProfileTests {
    let root = URL(fileURLWithPath: "/z")

    @Test func prefersInstallDefault() {
        let ini = """
        [Profile1]
        Name=Default Profile
        IsRelative=1
        Path=Profiles/other.Default Profile
        Default=1

        [Install6ED35B3CA1B20C59]
        Default=Profiles/wnmt4zb2.Default (release)
        Locked=1
        """
        #expect(ZenProfile.defaultProfile(profilesIni: ini, root: root)?.path == "/z/Profiles/wnmt4zb2.Default (release)")
    }

    @Test func fallsBackToDefaultFlag() {
        let ini = """
        [Profile0]
        Path=Profiles/a
        [Profile1]
        Path=Profiles/b
        Default=1
        """
        #expect(ZenProfile.defaultProfile(profilesIni: ini, root: root)?.path == "/z/Profiles/b")
    }

    @Test func handlesAbsolutePath() {
        let ini = "[Profile0]\nIsRelative=0\nPath=/elsewhere/p\n"
        #expect(ZenProfile.defaultProfile(profilesIni: ini, root: root)?.path == "/elsewhere/p")
    }

    @Test func usesFirstInstallSection() {
        let ini = "[Install1]\nDefault=Profiles/first\n[Install2]\nDefault=Profiles/second\n"
        #expect(ZenProfile.defaultProfile(profilesIni: ini, root: root)?.path == "/z/Profiles/first")
    }

    @Test func installWithAbsolutePath() {
        let ini = "[Install1]\nDefault=/Volumes/ext/zen-profile\n"
        #expect(ZenProfile.defaultProfile(profilesIni: ini, root: root)?.path == "/Volumes/ext/zen-profile")
    }

    @Test func toleratesCommentsAndCRLF() {
        let ini = "; comment\r\n[Profile0]\r\nPath=Profiles/x\r\nDefault=1\r\n"
        #expect(ZenProfile.defaultProfile(profilesIni: ini, root: root)?.path == "/z/Profiles/x")
    }

    @Test func ambiguousWithoutDefault() {
        let ini = "[Profile0]\nPath=a\n[Profile1]\nPath=b\n"
        #expect(ZenProfile.defaultProfile(profilesIni: ini, root: root) == nil)
    }
}

struct ChromiumProfilesTests {
    @Test func usesProfilesOrderThenNaturalSort() throws {
        let json = """
        {"profile": {
          "info_cache": {
            "Profile 10": {"name": "Ten"},
            "Profile 2": {"name": "Two"},
            "Default": {"name": "Main"},
            "Profile 3": {"name": ""}
          },
          "profiles_order": ["Default", "Missing"]
        }}
        """
        let profiles = try ChromiumProfiles.parse(localState: Data(json.utf8))
        #expect(profiles.map(\.directory) == ["Default", "Profile 2", "Profile 3", "Profile 10"])
        #expect(profiles.map(\.name) == ["Main", "Two", "Profile 3", "Ten"])
    }

    @Test func emptyWithoutProfileSection() throws {
        #expect(try ChromiumProfiles.parse(localState: Data("{}".utf8)).isEmpty)
    }
}

struct WeblocParserTests {
    @Test func readsXMLWebloc() {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict><key>URL</key><string>https://example.com/a?b=c</string></dict></plist>
        """
        #expect(WeblocParser.url(fromWebloc: Data(xml.utf8))?.absoluteString == "https://example.com/a?b=c")
    }

    @Test func readsBinaryWebloc() throws {
        let data = try PropertyListSerialization.data(
            fromPropertyList: ["URL": "https://zen-browser.app"], format: .binary, options: 0
        )
        #expect(WeblocParser.url(fromWebloc: data)?.host == "zen-browser.app")
    }

    @Test func rejectsGarbage() {
        #expect(WeblocParser.url(fromWebloc: Data("nope".utf8)) == nil)
    }
}
