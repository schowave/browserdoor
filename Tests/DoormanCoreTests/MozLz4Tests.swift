import Foundation
import Testing
@testable import DoormanCore

struct MozLz4Tests {
    @Test func decodesLiteralOnlyBlock() throws {
        let text = String(repeating: "zen workspaces ", count: 40) // > 15 and > 255 bytes
        let decoded = try MozLz4.decompress(mozLz4(json: text))
        #expect(String(decoding: decoded, as: UTF8.self) == text)
    }

    @Test func decodesOverlappingMatch() throws {
        // token: 3 literals, match length 5+4 = 9; "abc" then copy from offset 3.
        var bytes = MozLz4.magic + [12, 0, 0, 0]
        bytes += [0x35] + Array("abc".utf8) + [3, 0]
        let decoded = try MozLz4.decompress(Data(bytes))
        #expect(String(decoding: decoded, as: UTF8.self) == "abcabcabcabc")
    }

    @Test func decodesMatchFollowedByLiterals() throws {
        // 2 literals + minimal match (4) from offset 2, then a literal-only last sequence.
        var bytes = MozLz4.magic + [9, 0, 0, 0]
        bytes += [0x20] + Array("ab".utf8) + [2, 0]   // "ab" + match 4 → "ababab"
        bytes += [0x30] + Array("xyz".utf8)            // last sequence: literals only
        let decoded = try MozLz4.decompress(Data(bytes))
        #expect(String(decoding: decoded, as: UTF8.self) == "abababxyz")
    }

    @Test func rejectsBadMagic() {
        #expect(throws: MozLz4.DecodeError.badMagic) {
            try MozLz4.decompress(Data("notLz4!!\0\0\0\0".utf8))
        }
    }

    @Test func rejectsOffsetBeyondOutput() {
        let bytes = MozLz4.magic + [8, 0, 0, 0] + [0x10, 0x61, 9, 0]
        #expect(throws: MozLz4.DecodeError.corrupt) { try MozLz4.decompress(Data(bytes)) }
    }

    @Test func rejectsTruncatedLiterals() {
        let bytes = MozLz4.magic + [5, 0, 0, 0] + [0x50, 0x61, 0x62]
        #expect(throws: MozLz4.DecodeError.truncated) { try MozLz4.decompress(Data(bytes)) }
    }

    @Test func rejectsSizeMismatch() {
        var data = mozLz4(json: "hello")
        data[8] = 6
        #expect(throws: MozLz4.DecodeError.corrupt) { try MozLz4.decompress(data) }
    }
}
