import Foundation

/// Just enough zlib for Aseprite files: reading compressed data (inflate), and writing it in the
/// simplest valid form (stored blocks). Pure Swift, so the same code runs in the tests on Linux.
enum Zlib {
    /// Decompresses a zlib stream (2-byte header, deflate data, checksum). Nil if it's damaged.
    /// `limit` stops runaway output from a bad file.
    static func inflate(_ input: [UInt8], limit: Int = 64 * 1024 * 1024) -> [UInt8]? {
        guard input.count >= 2, input[0] & 0x0F == 8, (Int(input[0]) << 8 | Int(input[1])) % 31 == 0, input[1] & 0x20 == 0 else { return nil }
        var r = BitReader(bytes: input, pos: 2)
        var out: [UInt8] = []
        while true {
            guard let final = r.bits(1), let type = r.bits(2) else { return nil }
            switch type {
            case 0:
                // Stored: skip to a byte boundary, then length and its complement.
                r.alignToByte()
                guard let len = r.byte16(), let nlen = r.byte16(), len == (~nlen & 0xFFFF),
                      r.pos + len <= input.count, out.count + len <= limit else { return nil }
                out.append(contentsOf: input[r.pos..<(r.pos + len)])
                r.pos += len
            case 1:
                guard decodeBlock(&r, lengths: Huffman.fixedLengths, distances: Huffman.fixedDistances, into: &out, limit: limit) else { return nil }
            case 2:
                guard let tables = dynamicTables(&r),
                      decodeBlock(&r, lengths: tables.0, distances: tables.1, into: &out, limit: limit) else { return nil }
            default:
                return nil
            }
            if final == 1 { break }
        }
        return out
    }

    /// A valid zlib stream holding `data` uncompressed (stored blocks).
    static func store(_ data: [UInt8]) -> [UInt8] {
        var out: [UInt8] = [0x78, 0x01]
        var i = 0
        repeat {
            let n = min(65_535, data.count - i)
            let last = i + n >= data.count
            out.append(last ? 1 : 0)
            out.append(UInt8(n & 0xFF)); out.append(UInt8(n >> 8))
            out.append(UInt8(~n & 0xFF)); out.append(UInt8((~n >> 8) & 0xFF))
            out.append(contentsOf: data[i..<(i + n)])
            i += n
        } while i < data.count
        let sum = adler32(data)
        out += [UInt8(sum >> 24), UInt8((sum >> 16) & 0xFF), UInt8((sum >> 8) & 0xFF), UInt8(sum & 0xFF)]
        return out
    }

    static func adler32(_ data: [UInt8]) -> UInt32 {
        var a: UInt32 = 1, b: UInt32 = 0
        for byte in data {
            a = (a + UInt32(byte)) % 65_521
            b = (b + a) % 65_521
        }
        return (b << 16) | a
    }

    // MARK: Inflate internals

    private struct BitReader {
        let bytes: [UInt8]
        var pos: Int
        private var buffer: UInt32 = 0
        private var count = 0

        init(bytes: [UInt8], pos: Int) {
            self.bytes = bytes
            self.pos = pos
        }

        /// The next `n` bits (n ≤ 16), least significant first.
        mutating func bits(_ n: Int) -> Int? {
            while count < n {
                guard pos < bytes.count else { return nil }
                buffer |= UInt32(bytes[pos]) << UInt32(count)
                pos += 1
                count += 8
            }
            let v = Int(buffer & ((1 << UInt32(n)) - 1))
            buffer >>= UInt32(n)
            count -= n
            return v
        }

        mutating func alignToByte() {
            buffer = 0
            count = 0
        }

        /// A little-endian 16-bit number read from whole bytes.
        mutating func byte16() -> Int? {
            guard pos + 2 <= bytes.count else { return nil }
            let v = Int(bytes[pos]) | (Int(bytes[pos + 1]) << 8)
            pos += 2
            return v
        }
    }

    /// A canonical Huffman code, decoded a bit at a time (as in zlib's "puff").
    private struct Huffman {
        var counts = [Int](repeating: 0, count: 16)
        var symbols: [Int] = []

        init(_ lengths: [Int]) {
            for l in lengths { counts[l] += 1 }
            counts[0] = 0
            var offsets = [Int](repeating: 0, count: 16)
            for l in 1..<15 { offsets[l + 1] = offsets[l] + counts[l] }
            symbols = [Int](repeating: 0, count: lengths.count)
            for (s, l) in lengths.enumerated() where l != 0 {
                symbols[offsets[l]] = s
                offsets[l] += 1
            }
        }

        func decode(_ r: inout BitReader) -> Int? {
            var code = 0, first = 0, index = 0
            for length in 1...15 {
                guard let bit = r.bits(1) else { return nil }
                code |= bit
                let count = counts[length]
                if code - count < first { return symbols[index + (code - first)] }
                index += count
                first += count
                first <<= 1
                code <<= 1
            }
            return nil
        }

        static let fixedLengths: Huffman = {
            var l = [Int](repeating: 8, count: 288)
            for i in 144..<256 { l[i] = 9 }
            for i in 256..<280 { l[i] = 7 }
            return Huffman(l)
        }()
        static let fixedDistances = Huffman([Int](repeating: 5, count: 30))
    }

    private static let lengthBase = [3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258]
    private static let lengthExtra = [0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0]
    private static let distanceBase = [1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513, 769, 1025, 1537, 2049, 3073, 4097, 6145, 8193, 12289, 16385, 24577]
    private static let distanceExtra = [0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13]

    private static func decodeBlock(_ r: inout BitReader, lengths: Huffman, distances: Huffman, into out: inout [UInt8], limit: Int) -> Bool {
        while true {
            guard let symbol = lengths.decode(&r) else { return false }
            if symbol < 256 {
                guard out.count < limit else { return false }
                out.append(UInt8(symbol))
            } else if symbol == 256 {
                return true
            } else {
                let i = symbol - 257
                guard i < lengthBase.count, let extra = r.bits(lengthExtra[i]),
                      let d = distances.decode(&r), d < distanceBase.count, let dextra = r.bits(distanceExtra[d]) else { return false }
                let length = lengthBase[i] + extra, distance = distanceBase[d] + dextra
                guard distance <= out.count, out.count + length <= limit else { return false }
                // Byte by byte: the copy may overlap what it's writing.
                var from = out.count - distance
                for _ in 0..<length {
                    out.append(out[from])
                    from += 1
                }
            }
        }
    }

    private static func dynamicTables(_ r: inout BitReader) -> (Huffman, Huffman)? {
        guard let hlit = r.bits(5), let hdist = r.bits(5), let hclen = r.bits(4) else { return nil }
        let nlen = hlit + 257, ndist = hdist + 1, ncode = hclen + 4
        guard nlen <= 286, ndist <= 30 else { return nil }
        let order = [16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15]
        var codeLengths = [Int](repeating: 0, count: 19)
        for i in 0..<ncode {
            guard let v = r.bits(3) else { return nil }
            codeLengths[order[i]] = v
        }
        let codes = Huffman(codeLengths)
        var lengths: [Int] = []
        while lengths.count < nlen + ndist {
            guard let symbol = codes.decode(&r) else { return nil }
            switch symbol {
            case 0...15:
                lengths.append(symbol)
            case 16:
                guard let last = lengths.last, let n = r.bits(2) else { return nil }
                lengths += [Int](repeating: last, count: 3 + n)
            case 17:
                guard let n = r.bits(3) else { return nil }
                lengths += [Int](repeating: 0, count: 3 + n)
            default:
                guard let n = r.bits(7) else { return nil }
                lengths += [Int](repeating: 0, count: 11 + n)
            }
        }
        guard lengths.count == nlen + ndist, lengths[256] != 0 else { return nil }
        return (Huffman(Array(lengths[..<nlen])), Huffman(Array(lengths[nlen...])))
    }
}
