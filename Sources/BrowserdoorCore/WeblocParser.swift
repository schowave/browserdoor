import Foundation

/// Reads the target URL out of a `.webloc` file (XML or binary property list).
enum WeblocParser {
    static func url(fromWebloc data: Data) -> URL? {
        guard
            let plist = try? PropertyListSerialization.propertyList(from: data, format: nil),
            let dict = plist as? [String: Any],
            let string = dict["URL"] as? String
        else { return nil }
        return URL(string: string)
    }
}
