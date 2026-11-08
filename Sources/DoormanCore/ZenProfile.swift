import Foundation

/// Resolves the default Zen profile directory from `profiles.ini`.
public enum ZenProfile {
    /// `~/Library/Application Support/zen`
    public static func defaultRoot(home: URL) -> URL {
        home.appendingPathComponent("Library/Application Support/zen", isDirectory: true)
    }

    /// Returns the default profile directory, or nil if none can be determined.
    ///
    /// Preference order: `Default=` of the first `[Install…]` section (the profile
    /// the installed app actually uses), then the `[Profile…]` section with `Default=1`,
    /// then the only profile if there is exactly one.
    public static func defaultProfile(profilesIni: String, root: URL) -> URL? {
        let sections = INI.parse(profilesIni)

        if let install = sections.first(where: { $0.name.hasPrefix("Install") }),
           let path = install.values["Default"], !path.isEmpty {
            // Install sections always use paths relative to the root.
            return resolve(path, isRelative: !path.hasPrefix("/"), root: root)
        }

        let profiles = sections.filter { $0.name.hasPrefix("Profile") && $0.values["Path"] != nil }
        let chosen = profiles.first(where: { $0.values["Default"] == "1" })
            ?? (profiles.count == 1 ? profiles.first : nil)
        guard let chosen, let path = chosen.values["Path"] else { return nil }
        return resolve(path, isRelative: chosen.values["IsRelative"] != "0", root: root)
    }

    private static func resolve(_ path: String, isRelative: Bool, root: URL) -> URL {
        isRelative
            ? root.appendingPathComponent(path, isDirectory: true)
            : URL(fileURLWithPath: path, isDirectory: true)
    }
}

enum INI {
    struct Section: Equatable {
        var name: String
        var values: [String: String]
    }

    static func parse(_ text: String) -> [Section] {
        var sections: [Section] = []
        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix(";") || line.hasPrefix("#") { continue }
            if line.hasPrefix("["), line.hasSuffix("]") {
                sections.append(Section(name: String(line.dropFirst().dropLast()), values: [:]))
            } else if let eq = line.firstIndex(of: "="), !sections.isEmpty {
                let key = line[..<eq].trimmingCharacters(in: .whitespaces)
                let value = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)
                sections[sections.count - 1].values[key] = value
            }
        }
        return sections
    }
}
