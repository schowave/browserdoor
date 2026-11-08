import Foundation

/// Decoder for Mozilla's `mozLz4` container (`*.jsonlz4`, `*.mozlz4`).
///
/// Layout: 8-byte magic `mozLz40\0`, uint32 LE decompressed size, raw LZ4 block.
public enum MozLz4 {
    public enum DecodeError: Error, Equatable {
        case badMagic
        case truncated
        case corrupt
        case tooLarge
    }

    static let magic: [UInt8] = Array("mozLz40\0".utf8)
    /// Upper bound for the decompressed size. Real session files are a few MB.
    public static let maxDecompressedSize = 64 * 1024 * 1024

    public static func decompress(_ data: Data) throws(DecodeError) -> Data {
        let bytes = [UInt8](data)
        guard bytes.count >= 12, Array(bytes[0 ..< 8]) == magic else { throw .badMagic }
        let size = Int(bytes[8]) | Int(bytes[9]) << 8 | Int(bytes[10]) << 16 | Int(bytes[11]) << 24
        guard size <= maxDecompressedSize else { throw .tooLarge }
        return try Data(LZ4Block.decompress(bytes[12...], expectedSize: size))
    }
}

enum LZ4Block {
    static func decompress(_ src: ArraySlice<UInt8>, expectedSize: Int) throws(MozLz4.DecodeError) -> [UInt8] {
        var out = [UInt8]()
        out.reserveCapacity(expectedSize)
        var i = src.startIndex
        let end = src.endIndex

        func readLength(_ base: Int) throws(MozLz4.DecodeError) -> Int {
            var length = base
            guard base == 15 else { return length }
            while true {
                guard i < end else { throw .truncated }
                let b = src[i]
                i += 1
                length += Int(b)
                if b != 255 {
                    return length
                }
            }
        }

        while i < end {
            let token = src[i]
            i += 1

            let literalLength = try readLength(Int(token >> 4))
            guard literalLength <= end - i else { throw .truncated }
            guard literalLength <= expectedSize - out.count else { throw .corrupt }
            out.append(contentsOf: src[i ..< (i + literalLength)])
            i += literalLength

            // The last sequence consists of literals only.
            if i == end {
                break
            }

            guard end - i >= 2 else { throw .truncated }
            let offset = Int(src[i]) | Int(src[i + 1]) << 8
            i += 2
            guard offset > 0, offset <= out.count else { throw .corrupt }

            let matchLength = try readLength(Int(token & 0x0F)) + 4
            // Never grow past the declared size: a tiny crafted block could otherwise expand to GBs.
            guard matchLength <= expectedSize - out.count else { throw .corrupt }
            // Byte-wise copy: matches may overlap their own output.
            let start = out.count - offset
            for k in 0 ..< matchLength {
                out.append(out[start + k])
            }
        }

        guard out.count == expectedSize else { throw .corrupt }
        return out
    }
}
