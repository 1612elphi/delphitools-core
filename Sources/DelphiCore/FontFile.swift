import CoreGraphics
import CoreText
import Foundation

/// A font file read for inspection: names, metrics at 1000 points, the tables it carries.
public struct FontFile {
    public enum Failure: Error, Equatable, Sendable {
        case unreadable
        case notAFont
    }

    public let fileName: String
    public let postScriptName: String
    public let familyName: String
    public let styleName: String
    public let fullName: String
    public let unitsPerEm: CGFloat
    public let ascent: CGFloat
    public let descent: CGFloat
    public let leading: CGFloat
    public let capHeight: CGFloat
    public let xHeight: CGFloat
    public let italicAngle: CGFloat
    public let boundingBox: CGRect
    public let glyphCount: Int
    public let tables: [String]
    /// The decoded SFNT bytes, WOFF and WOFF2 unpacked.
    public let sfnt: Data
    /// 1000 pt, so metrics read as thousandths of an em.
    public let font: CTFont

    public init(contentsOf url: URL) throws(Failure) {
        guard let raw = try? Data(contentsOf: url) else { throw .unreadable }
        try self.init(data: raw, fileName: url.lastPathComponent)
    }

    public init(data raw: Data, fileName: String) throws(Failure) {
        guard let sfnt = try? WOFFDecoder.decode(raw), let provider = CGDataProvider(data: sfnt as CFData), let graphics = CGFont(provider) else {
            throw .notAFont
        }
        let font = CTFontCreateWithGraphicsFont(graphics, 1000, nil, nil)
        self.fileName = fileName
        self.sfnt = sfnt
        self.font = font
        postScriptName = CTFontCopyPostScriptName(font) as String
        familyName = CTFontCopyFamilyName(font) as String
        styleName = (CTFontCopyName(font, kCTFontSubFamilyNameKey) as String?) ?? "Regular"
        fullName = CTFontCopyFullName(font) as String
        unitsPerEm = CGFloat(CTFontGetUnitsPerEm(font))
        ascent = CTFontGetAscent(font)
        descent = CTFontGetDescent(font)
        leading = CTFontGetLeading(font)
        capHeight = CTFontGetCapHeight(font)
        xHeight = CTFontGetXHeight(font)
        italicAngle = CGFloat(CTFontGetSlantAngle(font))
        boundingBox = CTFontGetBoundingBox(font)
        glyphCount = CTFontGetGlyphCount(font)
        tables = Self.tableTags(font)
    }

    private static func tableTags(_ font: CTFont) -> [String] {
        guard let tags = CTFontCopyAvailableTables(font, []) else { return [] }
        return (0..<CFArrayGetCount(tags)).compactMap { index in
            let tag = UInt32(UInt(bitPattern: CFArrayGetValueAtIndex(tags, index)))
            let name = String((0..<4).compactMap { shift -> Character? in
                let byte = UInt8((tag >> (24 - shift * 8)) & 0xFF)
                return byte >= 0x20 && byte < 0x7F ? Character(UnicodeScalar(byte)) : nil
            })
            return name.isEmpty ? nil : name
        }.sorted()
    }

    /// Font units for a share of the 1000 pt size.
    public func units(_ points: CGFloat) -> Int { Int((points / 1000 * unitsPerEm).rounded()) }

    public static let specimenLetters = "Hxdp"

    /// Hxdp, or the first four letters the font has when it lacks those.
    public static func specimen(for font: CTFont) -> String {
        let set = CTFontCopyCharacterSet(font) as CharacterSet
        return specimen { set.contains($0) }
    }

    public static func specimen(covers: (Unicode.Scalar) -> Bool) -> String {
        if specimenLetters.unicodeScalars.allSatisfy(covers) { return specimenLetters }
        var found = ""
        for value in UInt32(0x21)...0x1FFFF {
            guard let scalar = Unicode.Scalar(value), scalar.properties.isAlphabetic, covers(scalar) else { continue }
            found.unicodeScalars.append(scalar)
            if found.unicodeScalars.count == 4 { break }
        }
        return found.isEmpty ? specimenLetters : found
    }

    /// Latin through Latin Extended-A, or the block of the font's first letter.
    public static func chartRange(for font: CTFont) -> ClosedRange<UInt32> {
        let first = specimen(for: font).unicodeScalars.first?.value ?? 0x41
        guard first > 0x17F else { return 0x20...0x17F }
        return UnicodeBlocks.all.first { $0.range.contains(first) }?.range ?? (first / 16 * 16)...(first / 16 * 16 + 0x7F)
    }

    /// A true minus for negatives.
    public static func signed(_ value: Int) -> String {
        value < 0 ? "\u{2212}\(-value)" : "\(value)"
    }

    public static func css(family: String, fileName: String) -> String {
        let format = ["woff2": "woff2", "woff": "woff", "otf": "opentype"][(fileName as NSString).pathExtension.lowercased()] ?? "truetype"
        return """
        @font-face {
          font-family: '\(family)';
          src: url('\(fileName)') format('\(format)');
          font-weight: normal;
          font-style: normal;
        }

        .my-text {
          font-family: '\(family)', sans-serif;
        }
        """
    }

    /// Vertical metrics as fractions of the em, descent positive.
    public struct Metrics: Equatable, Sendable {
        public var ascent: CGFloat
        public var capHeight: CGFloat
        public var xHeight: CGFloat
        public var descent: CGFloat
        public var unitsPerEm: CGFloat

        public init(ascent: CGFloat, capHeight: CGFloat, xHeight: CGFloat, descent: CGFloat, unitsPerEm: CGFloat) {
            self.ascent = ascent
            self.capHeight = capHeight
            self.xHeight = xHeight
            self.descent = descent
            self.unitsPerEm = unitsPerEm
        }

        public init(_ font: CTFont) {
            let size = max(CTFontGetSize(font), 1)
            self.init(
                ascent: CTFontGetAscent(font) / size, capHeight: CTFontGetCapHeight(font) / size,
                xHeight: CTFontGetXHeight(font) / size, descent: CTFontGetDescent(font) / size,
                unitsPerEm: CGFloat(CTFontGetUnitsPerEm(font))
            )
        }

        public func units(_ share: CGFloat) -> Int { Int((share * unitsPerEm).rounded()) }

        public func mixed(to other: Metrics, _ t: CGFloat) -> Metrics {
            func mix(_ a: CGFloat, _ b: CGFloat) -> CGFloat { a + (b - a) * t }
            return Metrics(ascent: mix(ascent, other.ascent), capHeight: mix(capHeight, other.capHeight),
                           xHeight: mix(xHeight, other.xHeight), descent: mix(descent, other.descent), unitsPerEm: other.unitsPerEm)
        }

        /// The em that fills `area` below `labelRoom`, shrinking for a wide `advance` (in ems) to half before it
        /// clips, and the baseline in `area`'s flipped coordinates.
        public func fit(advance: CGFloat, area: CGRect, labelRoom: CGFloat) -> (em: CGFloat, baseline: CGFloat) {
            let depth = max(ascent + descent, 0.01)
            let room = max(0, area.height - labelRoom)
            let tall = room / depth
            let wide = advance > 0 ? area.width / advance : tall
            let em = max(min(tall, wide), tall * 0.5)
            let top = area.minY + labelRoom + (room - em * depth) / 2
            return (em, top + ascent * em)
        }
    }

    #if DEBUG
    public static func selfCheck() {
        assert(specimen { _ in true } == "Hxdp")
        let shavian = specimen { $0.value >= 0x10450 && $0.value <= 0x1047F }
        assert(shavian.unicodeScalars.map(\.value) == [0x10450, 0x10451, 0x10452, 0x10453], "first four letters")
        assert(specimen { _ in false } == "Hxdp")
        assert(css(family: "Inter", fileName: "Inter.woff2").contains("format('woff2')"))
        assert(css(family: "Inter", fileName: "Inter.TTF").contains("format('truetype')"))
        assert(signed(-250) == "\u{2212}250" && signed(0) == "0")

        let metrics = Metrics(ascent: 0.8, capHeight: 0.7, xHeight: 0.5, descent: 0.2, unitsPerEm: 1000)
        let area = CGRect(x: 0, y: 10, width: 1000, height: 116)
        let tall = metrics.fit(advance: 1, area: area, labelRoom: 16)
        assert(tall.em == 100 && tall.baseline == 106, "fills the height")
        let wide = metrics.fit(advance: 20, area: area, labelRoom: 16)
        assert(wide.em == 50 && wide.baseline == 10 + 16 + 25 + 40, "shrinks to half, then clips")
        assert(metrics.fit(advance: 12.5, area: area, labelRoom: 16).em == 80, "fits the width")
        assert(metrics.units(-0.2) == -200)

        assert((try? FontFile(data: Data("nope".utf8), fileName: "x.ttf")) == nil)
        // macOS only
        let arial = URL(fileURLWithPath: "/System/Library/Fonts/Supplemental/Arial.ttf")
        if FileManager.default.fileExists(atPath: arial.path) {
            let file = try? FontFile(contentsOf: arial)
            assert(file?.familyName == "Arial" && file?.tables.contains("cmap") == true && file?.unitsPerEm == 2048)
        }
        WOFFDecoder.selfCheck()
    }
    #endif
}
