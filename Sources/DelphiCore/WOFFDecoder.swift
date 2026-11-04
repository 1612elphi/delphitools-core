import Foundation
import Compression
import CoreText

public enum WOFFError: Error {
    case invalidSignature
    case decompressionFailed
    case invalidTableData
}

public enum WOFFDecoder {

    private static let magicWOFF1: UInt32 = 0x774F4646  // "wOFF"
    private static let magicWOFF2: UInt32 = 0x774F4632  // "wOF2"
    private static let magicTTF:   UInt32 = 0x00010000
    private static let magicOTF:   UInt32 = 0x4F54544F  // "OTTO"
    private static let magicTTC:   UInt32 = 0x74746366  // "ttcf"

    // untrusted header sizes
    private static let maxSFNTSize = 256 << 20

    /// SFNT bytes from WOFF or WOFF2 data; TTF, OTF and TTC data come back unchanged.
    public static func decode(_ data: Data) throws -> Data {
        guard data.count >= 4 else { throw WOFFError.invalidSignature }
        let sig = readUInt32(data, offset: 0)
        switch sig {
        case magicTTF, magicOTF, magicTTC:
            return data
        case magicWOFF1:
            return try decodeWOFF1(data)
        case magicWOFF2:
            return try decodeWOFF2(data)
        default:
            throw WOFFError.invalidSignature
        }
    }

    private static func decodeWOFF1(_ data: Data) throws -> Data {
        guard data.count >= 44 else { throw WOFFError.invalidTableData }

        let flavor    = readUInt32(data, offset: 4)
        let numTables = Int(readUInt16(data, offset: 12))

        let dirOffset = 44
        guard data.count >= dirOffset + numTables * 20 else { throw WOFFError.invalidTableData }

        struct WOFFTable {
            var tag:          UInt32
            var offset:       Int
            var compLength:   Int
            var origLength:   Int
            var origChecksum: UInt32
        }

        var tables: [WOFFTable] = []
        for i in 0..<numTables {
            let base = dirOffset + i * 20
            tables.append(WOFFTable(
                tag:          readUInt32(data, offset: base),
                offset:       Int(readUInt32(data, offset: base + 4)),
                compLength:   Int(readUInt32(data, offset: base + 8)),
                origLength:   Int(readUInt32(data, offset: base + 12)),
                origChecksum: readUInt32(data, offset: base + 16)
            ))
        }

        guard tables.reduce(0, { $0 + $1.origLength }) <= maxSFNTSize else { throw WOFFError.invalidTableData }

        var tableData: [Data] = []
        for table in tables {
            guard table.offset + table.compLength <= data.count else { throw WOFFError.invalidTableData }
            let compressed = data[table.offset ..< table.offset + table.compLength]
            if table.compLength == table.origLength {
                tableData.append(Data(compressed))
            } else {
                guard let raw = zlibDecompress(Data(compressed), expectedSize: table.origLength)
                else { throw WOFFError.decompressionFailed }
                tableData.append(raw)
            }
        }

        return try buildSFNT(flavor: flavor, tables: tables.map { (tag: $0.tag, checksum: $0.origChecksum) }, tableData: tableData)
    }

    // woff2 spec 5.2
    private static let woff2KnownTags: [UInt32] = [
        tag("cmap"), tag("head"), tag("hhea"), tag("hmtx"), tag("maxp"),
        tag("name"), tag("OS/2"), tag("post"), tag("cvt "), tag("fpgm"),
        tag("glyf"), tag("loca"), tag("prep"), tag("CFF "), tag("VORG"),
        tag("EBDT"), tag("EBLC"), tag("gasp"), tag("hdmx"), tag("kern"),
        tag("LTSH"), tag("PCLT"), tag("VDMX"), tag("vhea"), tag("vmtx"),
        tag("BASE"), tag("GDEF"), tag("GPOS"), tag("GSUB"), tag("EBSC"),
        tag("JSTF"), tag("MATH"), tag("CBDT"), tag("CBLC"), tag("COLR"),
        tag("CPAL"), tag("SVG "), tag("sbix"), tag("acnt"), tag("avar"),
        tag("bdat"), tag("bloc"), tag("bsln"), tag("cvar"), tag("fdsc"),
        tag("feat"), tag("fmtx"), tag("fvar"), tag("gvar"), tag("hsty"),
        tag("just"), tag("lcar"), tag("morx"), tag("mort"), tag("opbd"),
        tag("prop"), tag("trak"), tag("Zapf"), tag("Silf"), tag("Glat"),
        tag("Gloc"), tag("Feat"), tag("Sill"),
    ]

    private static func tag(_ s: StaticString) -> UInt32 {
        let b = s.utf8Start
        return (UInt32(b[0]) << 24) | (UInt32(b[1]) << 16) | (UInt32(b[2]) << 8) | UInt32(b[3])
    }

    private static func decodeWOFF2(_ data: Data) throws -> Data {
        guard data.count >= 48 else { throw WOFFError.invalidTableData }

        let flavor              = readUInt32(data, offset: 4)
        let numTables           = Int(readUInt16(data, offset: 12))
        let totalCompressedSize = Int(readUInt32(data, offset: 20))

        struct WOFF2Table {
            var tag:             UInt32
            var transformVersion: UInt8
            var origLength:      Int
            var transformLength: Int
        }

        let glyf = tag("glyf")
        let loca = tag("loca")

        var cursor = 48
        var tables: [WOFF2Table] = []
        for _ in 0..<numTables {
            guard cursor < data.count else { throw WOFFError.invalidTableData }
            let flags = data[cursor]; cursor += 1
            let tagIndex = Int(flags & 0x3F)
            let transformVersion = (flags >> 6) & 0x03

            let tableTag: UInt32
            if tagIndex == 63 {
                guard cursor + 4 <= data.count else { throw WOFFError.invalidTableData }
                tableTag = readUInt32(data, offset: cursor); cursor += 4
            } else {
                guard tagIndex < woff2KnownTags.count else { throw WOFFError.invalidTableData }
                tableTag = woff2KnownTags[tagIndex]
            }

            let (origLen, c1) = readUIntBase128(data, cursor: cursor)
            guard c1 >= 0 else { throw WOFFError.invalidTableData }
            cursor = c1

            var transformLen = origLen
            // woff2 null transform rule
            let isGlyfLoca = tableTag == glyf || tableTag == loca
            if isGlyfLoca ? transformVersion == 0 : transformVersion != 0 {
                let (tLen, c2) = readUIntBase128(data, cursor: cursor)
                guard c2 >= 0 else { throw WOFFError.invalidTableData }
                cursor = c2
                transformLen = tLen
            }

            tables.append(WOFF2Table(
                tag: tableTag,
                transformVersion: transformVersion,
                origLength: origLen,
                transformLength: transformLen
            ))
        }

        // stream follows directory
        let streamStart = cursor
        let streamEnd   = streamStart + totalCompressedSize
        guard streamEnd <= data.count else { throw WOFFError.invalidTableData }

        let compressedStream = Data(data[streamStart..<streamEnd])

        let totalUncompressed = tables.reduce(0) { $0 + $1.transformLength }
        guard totalUncompressed <= maxSFNTSize else { throw WOFFError.invalidTableData }
        guard let decompressedStream = brotliDecompress(compressedStream, expectedSize: totalUncompressed)
        else { throw WOFFError.decompressionFailed }

        var tableData: [Data] = []
        var streamOffset = 0
        for table in tables {
            let len = table.transformLength
            guard streamOffset + len <= decompressedStream.count else { throw WOFFError.invalidTableData }
            tableData.append(Data(decompressedStream[streamOffset ..< streamOffset + len]))
            streamOffset += len
        }

        var xMins: [Int]?
        if let g = tables.firstIndex(where: { $0.tag == glyf && $0.transformVersion == 0 }) {
            guard let l = tables.firstIndex(where: { $0.tag == loca }) else { throw WOFFError.invalidTableData }
            let rebuilt = try reconstructGlyf([UInt8](tableData[g]))
            tableData[g] = Data(rebuilt.glyf)
            tableData[l] = Data(rebuilt.loca)
            xMins = rebuilt.xMins
        }
        if let h = tables.firstIndex(where: { $0.tag == tag("hmtx") && $0.transformVersion == 1 }) {
            guard let xMins, let hhea = tables.firstIndex(where: { $0.tag == tag("hhea") })
            else { throw WOFFError.invalidTableData }
            let numberOfHMetrics = Int(readUInt16(tableData[hhea], offset: 34))
            tableData[h] = Data(try reconstructHmtx([UInt8](tableData[h]), numberOfHMetrics: numberOfHMetrics, xMins: xMins))
        }

        return try buildSFNT(
            flavor: flavor,
            tables: tables.map { (tag: $0.tag, checksum: 0) },
            tableData: tableData
        )
    }

    private static func reconstructGlyf(_ table: [UInt8]) throws -> (glyf: [UInt8], loca: [UInt8], xMins: [Int]) {
        var header = ByteReader(table)
        _ = try header.u16()
        let options = try header.u16()
        let numGlyphs = try header.u16()
        let indexFormat = try header.u16()
        var streams: [ByteReader] = []
        var start = 36
        for _ in 0..<7 {
            let size = try header.u32()
            guard start + size <= table.count else { throw WOFFError.invalidTableData }
            streams.append(ByteReader(table, start..<start + size))
            start += size
        }
        var nContours = streams[0], nPoints = streams[1], flagStream = streams[2], glyphStream = streams[3]
        var composites = streams[4], bboxes = streams[5], instructions = streams[6]
        let bboxBitmap = try bboxes.take(4 * ((numGlyphs + 31) / 32))
        var overlapBitmap: ArraySlice<UInt8>?
        if options & 1 != 0 {
            var rest = ByteReader(table, start..<table.count)
            overlapBitmap = try rest.take((numGlyphs + 7) / 8)
        }
        func isSet(_ bitmap: ArraySlice<UInt8>?, _ i: Int) -> Bool {
            guard let bitmap else { return false }
            return bitmap[bitmap.startIndex + i >> 3] & (0x80 >> UInt8(i & 7)) != 0
        }

        let align = indexFormat == 0 ? 2 : 4
        var glyf: [UInt8] = []
        var offsets: [Int] = []
        var xMins = [Int](repeating: 0, count: numGlyphs)
        for i in 0..<numGlyphs {
            offsets.append(glyf.count)
            let contours = try nContours.i16()
            let explicitBox = isSet(bboxBitmap, i)
            if contours == 0 {
                guard !explicitBox else { throw WOFFError.invalidTableData }
                continue
            }
            var box = explicitBox ? try (0..<4).map { _ in try bboxes.i16() } : []
            var body: [UInt8] = []
            if contours > 0 {
                var total = 0
                for _ in 0..<contours {
                    total += try nPoints.u255()
                    body += be16(total - 1)
                }
                var points: [(x: Int, y: Int, onCurve: Bool)] = []
                var x = 0, y = 0
                for _ in 0..<total {
                    let flag = try flagStream.u8()
                    let (dx, dy) = try triplet(flag & 0x7F, &glyphStream)
                    x += dx
                    y += dy
                    points.append((x, y, flag & 0x80 == 0))
                }
                let instructionLength = try glyphStream.u255()
                body += be16(instructionLength)
                body += try instructions.take(instructionLength)
                body += encodePoints(points, overlap: isSet(overlapBitmap, i))
                if box.isEmpty {
                    let xs = points.map(\.x), ys = points.map(\.y)
                    box = [xs.min() ?? 0, ys.min() ?? 0, xs.max() ?? 0, ys.max() ?? 0]
                }
            } else {
                guard explicitBox else { throw WOFFError.invalidTableData }
                var hasInstructions = false
                var more = true
                while more {
                    let flags = try composites.u16()
                    var size = flags & 0x0001 != 0 ? 6 : 4
                    if flags & 0x0008 != 0 { size += 2 } else if flags & 0x0040 != 0 { size += 4 } else if flags & 0x0080 != 0 { size += 8 }
                    body += be16(flags)
                    body += try composites.take(size)
                    more = flags & 0x0020 != 0
                    hasInstructions = hasInstructions || flags & 0x0100 != 0
                }
                if hasInstructions {
                    let instructionLength = try glyphStream.u255()
                    body += be16(instructionLength)
                    body += try instructions.take(instructionLength)
                }
            }
            glyf += be16(contours)
            for value in box { glyf += be16(value) }
            glyf += body
            glyf += [UInt8](repeating: 0, count: (align - glyf.count % align) % align)
            xMins[i] = box[0]
        }
        offsets.append(glyf.count)

        var loca: [UInt8] = []
        for offset in offsets {
            if indexFormat == 0 {
                guard offset / 2 <= 0xFFFF else { throw WOFFError.invalidTableData }
                loca += be16(offset / 2)
            } else {
                loca += be16(offset >> 16) + be16(offset)
            }
        }
        return (glyf, loca, xMins)
    }

    private static func triplet(_ flag: Int, _ r: inout ByteReader) throws -> (Int, Int) {
        func signed(_ bits: Int, _ value: Int) -> Int { bits & 1 != 0 ? value : -value }
        switch flag {
        case ..<10:
            return (0, signed(flag, ((flag & 14) << 7) + (try r.u8())))
        case ..<20:
            return (signed(flag, (((flag - 10) & 14) << 7) + (try r.u8())), 0)
        case ..<84:
            let b0 = flag - 20, b1 = try r.u8()
            return (signed(flag, 1 + (b0 & 0x30) + (b1 >> 4)), signed(flag >> 1, 1 + ((b0 & 0x0C) << 2) + (b1 & 0x0F)))
        case ..<120:
            let b0 = flag - 84, b1 = try r.u8(), b2 = try r.u8()
            return (signed(flag, 1 + ((b0 / 12) << 8) + b1), signed(flag >> 1, 1 + (((b0 % 12) >> 2) << 8) + b2))
        case ..<124:
            let b1 = try r.u8(), b2 = try r.u8(), b3 = try r.u8()
            return (signed(flag, (b1 << 4) + (b2 >> 4)), signed(flag >> 1, ((b2 & 0x0F) << 8) + b3))
        default:
            let dx = try r.u16(), dy = try r.u16()
            return (signed(flag, dx), signed(flag >> 1, dy))
        }
    }

    private static func encodePoints(_ points: [(x: Int, y: Int, onCurve: Bool)], overlap: Bool) -> [UInt8] {
        var flags: [UInt8] = [], xs: [UInt8] = [], ys: [UInt8] = []
        var lastX = 0, lastY = 0
        for (n, point) in points.enumerated() {
            var flag: UInt8 = point.onCurve ? 0x01 : 0
            if n == 0 && overlap { flag |= 0x40 }
            let dx = point.x - lastX, dy = point.y - lastY
            lastX = point.x
            lastY = point.y
            if dx == 0 { flag |= 0x10 } else if abs(dx) < 256 { flag |= dx > 0 ? 0x12 : 0x02; xs.append(UInt8(abs(dx))) } else { xs += be16(dx) }
            if dy == 0 { flag |= 0x20 } else if abs(dy) < 256 { flag |= dy > 0 ? 0x24 : 0x04; ys.append(UInt8(abs(dy))) } else { ys += be16(dy) }
            flags.append(flag)
        }
        var packed: [UInt8] = []
        var i = 0
        while i < flags.count {
            var run = 0
            while i + run + 1 < flags.count, flags[i + run + 1] == flags[i], run < 255 { run += 1 }
            packed += run > 0 ? [flags[i] | 0x08, UInt8(run)] : [flags[i]]
            i += run + 1
        }
        return packed + xs + ys
    }

    private static func reconstructHmtx(_ table: [UInt8], numberOfHMetrics: Int, xMins: [Int]) throws -> [UInt8] {
        guard numberOfHMetrics <= xMins.count else { throw WOFFError.invalidTableData }
        var r = ByteReader(table)
        let flags = try r.u8()
        let advances = try (0..<numberOfHMetrics).map { _ in try r.u16() }
        let bearings = flags & 1 != 0 ? Array(xMins[..<numberOfHMetrics]) : try (0..<numberOfHMetrics).map { _ in try r.i16() }
        let trailing = flags & 2 != 0 ? Array(xMins[numberOfHMetrics...]) : try (numberOfHMetrics..<xMins.count).map { _ in try r.i16() }
        var out: [UInt8] = []
        for i in 0..<numberOfHMetrics { out += be16(advances[i]) + be16(bearings[i]) }
        for bearing in trailing { out += be16(bearing) }
        return out
    }

    private static func be16(_ value: Int) -> [UInt8] {
        [UInt8(truncatingIfNeeded: value >> 8), UInt8(truncatingIfNeeded: value)]
    }

    private struct ByteReader {
        let bytes: [UInt8]
        var position: Int
        let end: Int

        init(_ bytes: [UInt8], _ range: Range<Int>? = nil) {
            self.bytes = bytes
            position = range?.lowerBound ?? 0
            end = range?.upperBound ?? bytes.count
        }

        mutating func take(_ count: Int) throws -> ArraySlice<UInt8> {
            guard count >= 0, position + count <= end else { throw WOFFError.invalidTableData }
            defer { position += count }
            return bytes[position ..< position + count]
        }

        mutating func u8() throws -> Int { Int(bytes[try take(1).startIndex]) }
        mutating func u16() throws -> Int { let hi = try u8(); return hi << 8 | (try u8()) }
        mutating func i16() throws -> Int { Int(Int16(truncatingIfNeeded: try u16())) }
        mutating func u32() throws -> Int { let hi = try u16(); return hi << 16 | (try u16()) }

        // woff2 4.1: 255uint16
        mutating func u255() throws -> Int {
            switch try u8() {
            case 253: return try u16()
            case 254: return try u8() + 506
            case 255: return try u8() + 253
            case let code: return code
            }
        }
    }

    private static func buildSFNT(
        flavor: UInt32,
        tables: [(tag: UInt32, checksum: UInt32)],
        tableData: [Data]
    ) throws -> Data {
        let numTables = tables.count
        // uint16 searchRange
        guard numTables > 0, numTables < 4096, tables.count == tableData.count else { throw WOFFError.invalidTableData }

        let headerSize = 12 + numTables * 16

        var offsets: [Int] = []
        var current = headerSize
        for td in tableData {
            offsets.append(current)
            current += pad4(td.count)
        }

        var out = Data(count: current)

        let sr = highestPowerOf2(numTables) * 16
        let es = log2floor(numTables)
        let rs = numTables * 16 - sr
        writeUInt32(&out, offset: 0, value: flavor)
        writeUInt16(&out, offset: 4, value: UInt16(numTables))
        writeUInt16(&out, offset: 6, value: UInt16(sr))
        writeUInt16(&out, offset: 8, value: UInt16(es))
        writeUInt16(&out, offset: 10, value: UInt16(rs))

        for i in 0..<numTables {
            let base = 12 + i * 16
            writeUInt32(&out, offset: base,      value: tables[i].tag)
            writeUInt32(&out, offset: base + 4,  value: tables[i].checksum)
            writeUInt32(&out, offset: base + 8,  value: UInt32(offsets[i]))
            writeUInt32(&out, offset: base + 12, value: UInt32(tableData[i].count))
        }

        for i in 0..<numTables {
            let td = tableData[i]
            out.replaceSubrange(offsets[i] ..< offsets[i] + td.count, with: td)
        }

        return out
    }

    private static func zlibDecompress(_ data: Data, expectedSize: Int) -> Data? {
        // rfc 1950: strip header
        guard data.count > 2 else { return nil }
        let raw = data.dropFirst(2)
        return decompress(Data(raw), algorithm: COMPRESSION_ZLIB, expectedSize: expectedSize)
    }

    private static func brotliDecompress(_ data: Data, expectedSize: Int) -> Data? {
        decompress(data, algorithm: COMPRESSION_BROTLI, expectedSize: expectedSize)
    }

    private static func decompress(_ data: Data, algorithm: compression_algorithm, expectedSize: Int) -> Data? {
        var bufferSize = max(expectedSize, 4096)
        for _ in 0..<4 where bufferSize <= maxSFNTSize {
            var output = Data(count: bufferSize)
            let result = data.withUnsafeBytes { srcPtr -> Int in
                guard let src = srcPtr.baseAddress else { return 0 }
                return output.withUnsafeMutableBytes { dstPtr -> Int in
                    guard let dst = dstPtr.baseAddress else { return 0 }
                    return compression_decode_buffer(
                        dst.assumingMemoryBound(to: UInt8.self), bufferSize,
                        src.assumingMemoryBound(to: UInt8.self), data.count,
                        nil, algorithm
                    )
                }
            }
            if result > 0 && result <= bufferSize {
                output.count = result
                return output
            }
            bufferSize *= 2
        }
        return nil
    }

    /// (0, -1) on error
    private static func readUIntBase128(_ data: Data, cursor: Int) -> (Int, Int) {
        var accum: UInt32 = 0
        var cur = cursor
        for i in 0..<5 {
            guard cur < data.count else { return (0, -1) }
            let b = UInt32(data[cur]); cur += 1
            if i == 0 && b == 0x80 { return (0, -1) }  // leading zero forbidden
            accum = (accum << 7) | (b & 0x7F)
            if accum > 0x7FFF_FFFF { return (0, -1) }  // overflow
            if b & 0x80 == 0 { return (Int(accum), cur) }
        }
        return (0, -1)  // too many bytes
    }

    private static func readUInt32(_ data: Data, offset: Int) -> UInt32 {
        guard offset + 4 <= data.count else { return 0 }
        return data.withUnsafeBytes { ptr -> UInt32 in
            var val: UInt32 = 0
            withUnsafeMutableBytes(of: &val) { dst in
                dst.copyMemory(from: UnsafeRawBufferPointer(start: ptr.baseAddress!.advanced(by: offset), count: 4))
            }
            return val.bigEndian
        }
    }

    private static func readUInt16(_ data: Data, offset: Int) -> UInt16 {
        guard offset + 2 <= data.count else { return 0 }
        return data.withUnsafeBytes { ptr -> UInt16 in
            var val: UInt16 = 0
            withUnsafeMutableBytes(of: &val) { dst in
                dst.copyMemory(from: UnsafeRawBufferPointer(start: ptr.baseAddress!.advanced(by: offset), count: 2))
            }
            return val.bigEndian
        }
    }

    private static func writeUInt32(_ data: inout Data, offset: Int, value: UInt32) {
        var be = value.bigEndian
        withUnsafeBytes(of: &be) { src in
            data.replaceSubrange(offset ..< offset + 4, with: src)
        }
    }

    private static func writeUInt16(_ data: inout Data, offset: Int, value: UInt16) {
        var be = value.bigEndian
        withUnsafeBytes(of: &be) { src in
            data.replaceSubrange(offset ..< offset + 2, with: src)
        }
    }

    private static func pad4(_ n: Int) -> Int { (n + 3) & ~3 }

    private static func highestPowerOf2(_ n: Int) -> Int {
        guard n > 0 else { return 0 }
        var p = 1
        while p * 2 <= n { p *= 2 }
        return p
    }

    private static func log2floor(_ n: Int) -> Int {
        guard n > 0 else { return 0 }
        var result = 0
        var v = n
        while v > 1 { v >>= 1; result += 1 }
        return result
    }
    #if DEBUG
    // -woff2Check <dir>
    public static func selfCheck() {
        func be(_ value: UInt32) -> [UInt8] { withUnsafeBytes(of: value.bigEndian, Array.init) }
        let manyTables = be(magicWOFF1) + be(magicTTF) + [0, 0, 0, 0, 0x10, 0] + [UInt8](repeating: 0, count: 30 + 4096 * 20)
        let hugeTable = be(magicWOFF2) + be(magicTTF) + [0, 0, 0, 0, 0, 1] + [UInt8](repeating: 0, count: 34) + [0, 0x87, 0xFF, 0xFF, 0xFF, 0x7F]
        assert((try? decode(Data(manyTables))) == nil && (try? decode(Data(hugeTable))) == nil)
        guard let dir = UserDefaults.standard.string(forKey: "woff2Check") else { return }
        let folder = URL(fileURLWithPath: dir)
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        func font(_ data: Data) -> CTFont? {
            guard let provider = CGDataProvider(data: data as CFData), let cgFont = CGFont(provider) else { return nil }
            return CTFontCreateWithGraphicsFont(cgFont, 1000, nil, nil)
        }
        for url in files where url.pathExtension == "woff2" {
            let name = url.deletingPathExtension().lastPathComponent.split(separator: "-")[0]
            guard let raw = try? Data(contentsOf: url), let decoded = try? decode(raw), let woff = font(decoded),
                  let ttfData = try? Data(contentsOf: folder.appendingPathComponent("\(name).ttf")), let ttf = font(ttfData)
            else { assertionFailure("\(url.lastPathComponent) did not decode"); continue }
            let count = CTFontGetGlyphCount(ttf)
            let mismatches = (0..<count).filter { g in
                CTFontCreatePathForGlyph(woff, CGGlyph(g), nil)?.boundingBoxOfPath != CTFontCreatePathForGlyph(ttf, CGGlyph(g), nil)?.boundingBoxOfPath
            }
            let hmtx = CTFontTableTag(kCTFontTableHmtx)
            let sameHmtx = CTFontCopyTable(woff, hmtx, []) as Data? == CTFontCopyTable(ttf, hmtx, []) as Data?
            print("WOFF2", url.lastPathComponent, CTFontGetGlyphCount(woff), "of", count, "glyphs,", mismatches.count, "bounds differ, hmtx", sameHmtx ? "same" : "differs")
            assert(CTFontGetGlyphCount(woff) == count && mismatches.isEmpty && sameHmtx)
        }
    }
    #endif
}
