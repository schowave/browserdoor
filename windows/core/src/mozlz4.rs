//! Mozilla's `mozLz4` container (`*.jsonlz4`): magic `mozLz40\0`, uint32 LE size, raw LZ4 block.

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum DecodeError {
    BadMagic,
    Truncated,
    Corrupt,
    TooLarge,
}

pub const MAGIC: &[u8; 8] = b"mozLz40\0";
/// Upper bound for the decompressed size. Real session files are a few MB.
pub const MAX_DECOMPRESSED_SIZE: usize = 64 * 1024 * 1024;

pub fn decompress(data: &[u8]) -> Result<Vec<u8>, DecodeError> {
    if data.len() < 12 || &data[..8] != MAGIC {
        return Err(DecodeError::BadMagic);
    }
    let size = u32::from_le_bytes([data[8], data[9], data[10], data[11]]) as usize;
    if size > MAX_DECOMPRESSED_SIZE {
        return Err(DecodeError::TooLarge);
    }
    lz4_block(&data[12..], size)
}

fn lz4_block(src: &[u8], expected: usize) -> Result<Vec<u8>, DecodeError> {
    let mut out: Vec<u8> = Vec::with_capacity(expected);
    let mut i = 0;
    let read_length = |i: &mut usize, base: usize| -> Result<usize, DecodeError> {
        let mut length = base;
        if base != 15 {
            return Ok(length);
        }
        loop {
            let b = *src.get(*i).ok_or(DecodeError::Truncated)?;
            *i += 1;
            length += b as usize;
            if b != 255 {
                return Ok(length);
            }
        }
    };
    while i < src.len() {
        let token = src[i];
        i += 1;
        let literal = read_length(&mut i, (token >> 4) as usize)?;
        if literal > src.len() - i {
            return Err(DecodeError::Truncated);
        }
        if literal > expected - out.len() {
            return Err(DecodeError::Corrupt);
        }
        out.extend_from_slice(&src[i..i + literal]);
        i += literal;
        // The last sequence consists of literals only.
        if i == src.len() {
            break;
        }
        if src.len() - i < 2 {
            return Err(DecodeError::Truncated);
        }
        let offset = src[i] as usize | (src[i + 1] as usize) << 8;
        i += 2;
        if offset == 0 || offset > out.len() {
            return Err(DecodeError::Corrupt);
        }
        let matched = read_length(&mut i, (token & 0x0F) as usize)? + 4;
        // Never grow past the declared size: a tiny crafted block could expand to GBs.
        if matched > expected - out.len() {
            return Err(DecodeError::Corrupt);
        }
        // Byte-wise: matches may overlap their own output.
        let start = out.len() - offset;
        for k in 0..matched {
            out.push(out[start + k]);
        }
    }
    if out.len() != expected {
        return Err(DecodeError::Corrupt);
    }
    Ok(out)
}

/// A mozLz4 container around a literal-only LZ4 block: valid, uncompressed. For fixtures.
pub fn wrap_literal(payload: &[u8]) -> Vec<u8> {
    let n = payload.len();
    let mut out = MAGIC.to_vec();
    out.extend_from_slice(&(n as u32).to_le_bytes());
    if n < 15 {
        out.push((n as u8) << 4);
    } else {
        out.push(0xF0);
        let mut rest = n - 15;
        while rest >= 255 {
            out.push(255);
            rest -= 255;
        }
        out.push(rest as u8);
    }
    out.extend_from_slice(payload);
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn literal_round_trip() {
        for n in [0usize, 5, 14, 15, 16, 300, 270, 1000] {
            let payload: Vec<u8> = (0..n).map(|i| (i % 251) as u8).collect();
            assert_eq!(decompress(&wrap_literal(&payload)).unwrap(), payload, "n={n}");
        }
    }

    #[test]
    fn overlapping_match() {
        // "ab" then a match of offset 2, length 6 → "abababab"
        let mut data = MAGIC.to_vec();
        data.extend_from_slice(&8u32.to_le_bytes());
        data.extend_from_slice(&[0x22, b'a', b'b', 2, 0]);
        assert_eq!(decompress(&data).unwrap(), b"abababab");
    }

    #[test]
    fn rejects_bad_input() {
        assert_eq!(decompress(b"nope"), Err(DecodeError::BadMagic));
        let mut big = MAGIC.to_vec();
        big.extend_from_slice(&u32::MAX.to_le_bytes());
        assert_eq!(decompress(&big), Err(DecodeError::TooLarge));
        // declares 100 bytes, delivers 2
        let mut short = MAGIC.to_vec();
        short.extend_from_slice(&100u32.to_le_bytes());
        short.extend_from_slice(&[0x20, b'a', b'b']);
        assert_eq!(decompress(&short), Err(DecodeError::Corrupt));
        // match beyond the declared size
        let mut bomb = MAGIC.to_vec();
        bomb.extend_from_slice(&3u32.to_le_bytes());
        bomb.extend_from_slice(&[0x1F, b'a', 1, 0, 200]);
        assert_eq!(decompress(&bomb), Err(DecodeError::Corrupt));
    }
}
