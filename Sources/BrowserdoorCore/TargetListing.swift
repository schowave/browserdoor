import Foundation

public extension CatalogState {
    /// What `Browserdoor --list-targets` prints: one tab-separated line per target in picker
    /// order, hidden ones included, with key, ID, name, flags and the command a link would open
    /// with. Nothing is launched.
    /// - Parameter isRunning: whether an app runs right now; decides Zen's command.
    func listing(isRunning: (URL) -> Bool) -> String {
        let keys = effectiveKeys
        let defaultID = defaultIndex.map { pickerEntries[$0].id }
        let sample = URL(string: "https://example.com")!

        var lines = configIsUnreadable ? ["# config file unreadable, defaults in use"] : []
        lines += rows.map { row in
            let flags = [row.id == defaultID ? "default" : nil, row.hidden ? "hidden" : nil].compactMap(\.self)
            let commands = row.target.launchCommands(for: [sample], appIsRunning: isRunning(row.target.appURL))
            return [
                keys[row.id].map(String.init) ?? "-",
                row.id,
                row.displayName,
                flags.isEmpty ? "-" : flags.joined(separator: ","),
                commands.map(\.shellLine).joined(separator: " ; "),
            ].joined(separator: "\t")
        }
        return lines.joined(separator: "\n")
    }
}

extension LaunchCommand {
    /// The command as it would be typed in a shell; `.open` is shown as its `open -a` equivalent.
    var shellLine: String {
        let words: [String] = switch self {
        case let .run(executable, arguments): [executable.path] + arguments
        case let .open(urls, app): ["open", "-a", app.path] + urls.map(\.absoluteString)
        }
        return words.map(Self.quoted).joined(separator: " ")
    }

    private static func quoted(_ word: String) -> String {
        let plain = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_./:=,@%+{}"))
        if !word.isEmpty, word.unicodeScalars.allSatisfy(plain.contains) {
            return word
        }
        return "'" + word.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
