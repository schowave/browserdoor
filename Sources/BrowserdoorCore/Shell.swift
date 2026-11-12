import Foundation

enum Shell {
    /// A word as a POSIX shell reads it literally: unchanged when it is plain, else single-quoted.
    static func quote(_ word: String) -> String {
        let plain = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_./:=,@%+{}"))
        if !word.isEmpty, word.unicodeScalars.allSatisfy(plain.contains) {
            return word
        }
        return "'" + word.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
