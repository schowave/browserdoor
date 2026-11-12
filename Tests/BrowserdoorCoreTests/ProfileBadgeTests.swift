@testable import BrowserdoorCore
import Foundation
import Testing

struct ProfileBadgeTests {
    let chrome = URL(fileURLWithPath: "/Applications/Google Chrome.app")
    let safari = URL(fileURLWithPath: "/Applications/Safari.app")

    func target(_ id: String, _ app: URL) -> Target {
        Target(id: id, name: id, kind: .app(app))
    }

    @Test func onlyAppsListedMoreThanOnceGetBadges() {
        let badges = ProfileBadge.badges(for: [
            (target("chromium:a", chrome), "Work"),
            (target("chromium:b", chrome), "private"),
            (target("app:safari", safari), "Safari"),
        ])
        #expect(Set(badges.keys) == ["chromium:a", "chromium:b"])
        #expect(badges["chromium:a"]?.letter == "W")
        #expect(badges["chromium:b"]?.letter == "P")
    }

    @Test func zenSpacesGetNone() {
        let zen = URL(fileURLWithPath: "/Applications/Zen.app")
        func space(_ id: String) -> Target {
            Target(id: id, name: id, kind: ZenSpaceKind(app: zen, executable: zen, space: ZenSpace(uuid: id, name: id),
                                                        profile: nil, version: "1"))
        }
        #expect(ProfileBadge.badges(for: [(space("zen:a"), "A"), (space("zen:b"), "B")]).isEmpty)
    }

    @Test func colorIsStablePerTarget() {
        #expect(ProfileBadge.color(for: "chromium:a") == ProfileBadge.color(for: "chromium:a"))
        let colors = Set((0 ..< 50).map { ProfileBadge.color(for: "chromium:x:Profile \($0)") }.map { "\($0.r),\($0.g),\($0.b)" })
        #expect(colors.count > 4)
    }

    @Test func initialSkipsSymbols() {
        #expect(ProfileBadge.initial(of: "🦊 firefox") == "F")
        #expect(ProfileBadge.initial(of: "2nd") == "2")
        #expect(ProfileBadge.initial(of: "—") == "?")
        #expect(ProfileBadge.initial(of: "Firefox › Original profile") == "O")
        #expect(ProfileBadge.initial(of: "Google Chrome › 2. work") == "2")
    }
}
