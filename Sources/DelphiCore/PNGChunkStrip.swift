import Foundation

/// Drops a PNG's ancillary chunks byte for byte; an ImageIO re-encode would add chunks of its own.
public enum PNGChunkStrip {
    private static let signature = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
    private static let kept: Set<String> = [
        "IHDR", "PLTE", "IDAT", "IEND", "tRNS",
        "gAMA", "cHRM", "sRGB", "iCCP", "sBIT", "cICP", "mDCV", "cLLI",
        "pHYs", "acTL", "fcTL", "fdAT",
    ]

    /// nil for anything but a well-formed PNG.
    public static func strip(_ data: Data) -> (data: Data, removed: [String])? {
        let bytes = [UInt8](data)
        guard bytes.count > 8, Data(bytes[0..<8]) == signature else { return nil }
        var out = signature
        var removed: [String] = []
        var cursor = 8
        while cursor + 12 <= bytes.count {
            let length = bytes[cursor..<cursor + 4].reduce(0) { $0 << 8 | Int($1) }
            let end = cursor + 12 + length
            guard end <= bytes.count, let type = String(bytes: bytes[cursor + 4..<cursor + 8], encoding: .ascii) else { return nil }
            if kept.contains(type) {
                out.append(contentsOf: bytes[cursor..<end])
            } else if !removed.contains(type) {
                removed.append(type)
            }
            cursor = end
            if type == "IEND" { return (out, removed) }
        }
        return nil
    }

    #if DEBUG
    public static func selfCheck() {
        func chunk(_ type: String, _ body: [UInt8] = []) -> [UInt8] {
            [0, 0, 0, UInt8(body.count)] + Array(type.utf8) + body + [0, 0, 0, 0]
        }
        let png = Data([UInt8](signature) + chunk("IHDR", Array(repeating: 1, count: 13)) + chunk("tEXt", [65]) + chunk("IDAT", [7]) + chunk("eXIf", [1]) + chunk("IEND"))
        let stripped = strip(png)
        assert(stripped?.removed == ["tEXt", "eXIf"])
        assert(stripped?.data == Data([UInt8](signature) + chunk("IHDR", Array(repeating: 1, count: 13)) + chunk("IDAT", [7]) + chunk("IEND")))
        assert(strip(png.prefix(40)) == nil && strip(Data([0xFF, 0xD8, 0xFF])) == nil)
    }
    #endif
}
