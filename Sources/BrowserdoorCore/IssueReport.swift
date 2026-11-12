import Foundation

/// The "Report an Issue…" link: GitHub's bug form with the versions filled in. Nothing else is
/// sent; targets and paths stay on the Mac until the user pastes them.
public enum IssueReport {
    public static func url(appVersion: String, macOSVersion: String) -> URL {
        var components = URLComponents(string: "https://github.com/schowave/browserdoor/issues/new")!
        components.queryItems = [
            URLQueryItem(name: "template", value: "bug.yml"),
            // `versions` is the field ID in .github/ISSUE_TEMPLATE/bug.yml.
            URLQueryItem(name: "versions", value: "Browserdoor \(appVersion), macOS \(macOSVersion)"),
        ]
        return components.url!
    }
}
