import Foundation

public struct PaperSize: Identifiable, Sendable {
    public let id: String
    public let name: String
    public let widthMM: Double
    public let heightMM: Double

    public init(id: String, name: String, widthMM: Double, heightMM: Double) {
        (self.id, self.name, self.widthMM, self.heightMM) = (id, name, widthMM, heightMM)
    }

    public var widthInches: Double { widthMM / 25.4 }
    public var heightInches: Double { heightMM / 25.4 }
    public var widthPoints: Double { widthInches * 72.0 }
    public var heightPoints: Double { heightInches * 72.0 }
    public var widthPx96: Int { Int((widthInches * 96.0).rounded()) }
    public var heightPx96: Int { Int((heightInches * 96.0).rounded()) }

    public var mmString: String { "\(fmtMM(widthMM)) × \(fmtMM(heightMM)) mm" }
    public var inchesString: String { "\(fmtFraction(widthInches)) × \(fmtFraction(heightInches))″" }
    public var pointsString: String { "\(fmtMM(widthPoints)) × \(fmtMM(heightPoints)) pt" }
    public var pxString: String { "\(widthPx96) × \(heightPx96) px" }

    private func fmtMM(_ v: Double) -> String {
        v.truncatingRemainder(dividingBy: 1) == 0 ? String(format: "%.0f", v) : String(format: "%.1f", v)
    }

    /// eighths as vulgar fractions
    private func fmtFraction(_ inches: Double) -> String {
        let whole = Int(inches)
        let decimal = inches - Double(whole)
        let eighths = (decimal * 8).rounded() / 8
        let fractions: [Double: String] = [
            0: "", 0.125: "⅛", 0.25: "¼", 0.375: "⅜",
            0.5: "½", 0.625: "⅝", 0.75: "¾", 0.875: "⅞",
        ]
        if abs(decimal - eighths) < 0.01, let frac = fractions[eighths] {
            if whole > 0 { return frac.isEmpty ? "\(whole)" : "\(whole)\(frac)" }
            return frac.isEmpty ? "0" : frac
        }
        return String(format: "%.2f", inches)
    }
}

public struct PaperSeriesData: Identifiable, Sendable {
    public let id: String
    public let name: String
    public let sizes: [PaperSize]

    public init(id: String, name: String, sizes: [PaperSize]) {
        (self.id, self.name, self.sizes) = (id, name, sizes)
    }
}

public enum PaperSizeDatabase {
    public static let allSeries: [PaperSeriesData] = [
        PaperSeriesData(id: "iso-a", name: "ISO A", sizes: [
            PaperSize(id: "4A0", name: "4A0", widthMM: 1682, heightMM: 2378),
            PaperSize(id: "2A0", name: "2A0", widthMM: 1189, heightMM: 1682),
            PaperSize(id: "A0", name: "A0", widthMM: 841, heightMM: 1189),
            PaperSize(id: "A0+", name: "A0+", widthMM: 914, heightMM: 1292),
            PaperSize(id: "A1", name: "A1", widthMM: 594, heightMM: 841),
            PaperSize(id: "A1+", name: "A1+", widthMM: 609, heightMM: 914),
            PaperSize(id: "A2", name: "A2", widthMM: 420, heightMM: 594),
            PaperSize(id: "A3", name: "A3", widthMM: 297, heightMM: 420),
            PaperSize(id: "A3+", name: "A3+", widthMM: 329, heightMM: 483),
            PaperSize(id: "A4", name: "A4", widthMM: 210, heightMM: 297),
            PaperSize(id: "A5", name: "A5", widthMM: 148, heightMM: 210),
            PaperSize(id: "A6", name: "A6", widthMM: 105, heightMM: 148),
            PaperSize(id: "A7", name: "A7", widthMM: 74, heightMM: 105),
            PaperSize(id: "A8", name: "A8", widthMM: 52, heightMM: 74),
            PaperSize(id: "A9", name: "A9", widthMM: 37, heightMM: 52),
            PaperSize(id: "A10", name: "A10", widthMM: 26, heightMM: 37),
        ]),
        PaperSeriesData(id: "iso-b", name: "ISO B", sizes: [
            PaperSize(id: "B0", name: "B0", widthMM: 1000, heightMM: 1414),
            PaperSize(id: "B1", name: "B1", widthMM: 707, heightMM: 1000),
            PaperSize(id: "B2", name: "B2", widthMM: 500, heightMM: 707),
            PaperSize(id: "B3", name: "B3", widthMM: 353, heightMM: 500),
            PaperSize(id: "B4", name: "B4", widthMM: 250, heightMM: 353),
            PaperSize(id: "B5", name: "B5", widthMM: 176, heightMM: 250),
            PaperSize(id: "B6", name: "B6", widthMM: 125, heightMM: 176),
            PaperSize(id: "B7", name: "B7", widthMM: 88, heightMM: 125),
            PaperSize(id: "B8", name: "B8", widthMM: 62, heightMM: 88),
            PaperSize(id: "B9", name: "B9", widthMM: 44, heightMM: 62),
            PaperSize(id: "B10", name: "B10", widthMM: 31, heightMM: 44),
        ]),
        PaperSeriesData(id: "iso-c", name: "ISO C", sizes: [
            PaperSize(id: "C0", name: "C0", widthMM: 917, heightMM: 1297),
            PaperSize(id: "C1", name: "C1", widthMM: 648, heightMM: 917),
            PaperSize(id: "C2", name: "C2", widthMM: 458, heightMM: 648),
            PaperSize(id: "C3", name: "C3", widthMM: 324, heightMM: 458),
            PaperSize(id: "C4", name: "C4", widthMM: 229, heightMM: 324),
            PaperSize(id: "C5", name: "C5", widthMM: 162, heightMM: 229),
            PaperSize(id: "C6", name: "C6", widthMM: 114, heightMM: 162),
            PaperSize(id: "C7", name: "C7", widthMM: 81, heightMM: 114),
            PaperSize(id: "C8", name: "C8", widthMM: 57, heightMM: 81),
        ]),
        PaperSeriesData(id: "ra", name: "RA", sizes: [
            PaperSize(id: "RA0", name: "RA0", widthMM: 860, heightMM: 1220),
            PaperSize(id: "RA1", name: "RA1", widthMM: 610, heightMM: 860),
            PaperSize(id: "RA2", name: "RA2", widthMM: 430, heightMM: 610),
            PaperSize(id: "RA3", name: "RA3", widthMM: 305, heightMM: 430),
            PaperSize(id: "RA4", name: "RA4", widthMM: 215, heightMM: 305),
        ]),
        PaperSeriesData(id: "sra", name: "SRA", sizes: [
            PaperSize(id: "SRA0", name: "SRA0", widthMM: 900, heightMM: 1280),
            PaperSize(id: "SRA1", name: "SRA1", widthMM: 640, heightMM: 900),
            PaperSize(id: "SRA1+", name: "SRA1+", widthMM: 660, heightMM: 920),
            PaperSize(id: "SRA2", name: "SRA2", widthMM: 450, heightMM: 640),
            PaperSize(id: "SRA2+", name: "SRA2+", widthMM: 480, heightMM: 650),
            PaperSize(id: "SRA3", name: "SRA3", widthMM: 320, heightMM: 450),
            PaperSize(id: "SRA3+", name: "SRA3+", widthMM: 320, heightMM: 460),
            PaperSize(id: "SRA4", name: "SRA4", widthMM: 225, heightMM: 320),
        ]),
        PaperSeriesData(id: "us-classic", name: "US Classic", sizes: [
            PaperSize(id: "letter", name: "Letter", widthMM: 215.9, heightMM: 279.4),
            PaperSize(id: "legal", name: "Legal", widthMM: 215.9, heightMM: 355.6),
            PaperSize(id: "tabloid", name: "Tabloid", widthMM: 279.4, heightMM: 431.8),
            PaperSize(id: "ledger", name: "Ledger", widthMM: 431.8, heightMM: 279.4),
            PaperSize(id: "junior-legal", name: "Junior Legal", widthMM: 127, heightMM: 203.2),
            PaperSize(id: "half-letter", name: "Half Letter", widthMM: 139.7, heightMM: 215.9),
            PaperSize(id: "gov-letter", name: "Gov Letter", widthMM: 203.2, heightMM: 266.7),
            PaperSize(id: "gov-legal", name: "Gov Legal", widthMM: 215.9, heightMM: 330.2),
        ]),
        PaperSeriesData(id: "us-ansi", name: "US ANSI", sizes: [
            PaperSize(id: "ansi-a", name: "ANSI A", widthMM: 216, heightMM: 279),
            PaperSize(id: "ansi-b", name: "ANSI B", widthMM: 279, heightMM: 432),
            PaperSize(id: "ansi-c", name: "ANSI C", widthMM: 432, heightMM: 559),
            PaperSize(id: "ansi-d", name: "ANSI D", widthMM: 559, heightMM: 864),
            PaperSize(id: "ansi-e", name: "ANSI E", widthMM: 864, heightMM: 1118),
        ]),
        PaperSeriesData(id: "us-arch", name: "US Architectural", sizes: [
            PaperSize(id: "arch-a", name: "Arch A", widthMM: 229, heightMM: 305),
            PaperSize(id: "arch-b", name: "Arch B", widthMM: 305, heightMM: 457),
            PaperSize(id: "arch-c", name: "Arch C", widthMM: 457, heightMM: 610),
            PaperSize(id: "arch-d", name: "Arch D", widthMM: 610, heightMM: 914),
            PaperSize(id: "arch-e", name: "Arch E", widthMM: 914, heightMM: 1219),
            PaperSize(id: "arch-e1", name: "Arch E1", widthMM: 762, heightMM: 1067),
        ]),
        PaperSeriesData(id: "japanese", name: "Japanese JIS", sizes: [
            PaperSize(id: "jb0", name: "JIS B0", widthMM: 1030, heightMM: 1456),
            PaperSize(id: "jb1", name: "JIS B1", widthMM: 728, heightMM: 1030),
            PaperSize(id: "jb2", name: "JIS B2", widthMM: 515, heightMM: 728),
            PaperSize(id: "jb3", name: "JIS B3", widthMM: 364, heightMM: 515),
            PaperSize(id: "jb4", name: "JIS B4", widthMM: 257, heightMM: 364),
            PaperSize(id: "jb5", name: "JIS B5", widthMM: 182, heightMM: 257),
            PaperSize(id: "jb6", name: "JIS B6", widthMM: 128, heightMM: 182),
            PaperSize(id: "shiroku-ban-4", name: "Shiroku ban 4", widthMM: 264, heightMM: 379),
            PaperSize(id: "shiroku-ban-5", name: "Shiroku ban 5", widthMM: 189, heightMM: 262),
            PaperSize(id: "kiku-4", name: "Kiku 4", widthMM: 227, heightMM: 306),
            PaperSize(id: "kiku-5", name: "Kiku 5", widthMM: 151, heightMM: 227),
        ]),
        PaperSeriesData(id: "chinese", name: "Chinese", sizes: [
            PaperSize(id: "d0", name: "D0", widthMM: 764, heightMM: 1064),
            PaperSize(id: "d1", name: "D1", widthMM: 532, heightMM: 760),
            PaperSize(id: "d2", name: "D2", widthMM: 380, heightMM: 532),
            PaperSize(id: "d3", name: "D3", widthMM: 266, heightMM: 380),
            PaperSize(id: "d4", name: "D4", widthMM: 190, heightMM: 266),
            PaperSize(id: "d5", name: "D5", widthMM: 133, heightMM: 190),
            PaperSize(id: "d6", name: "D6", widthMM: 95, heightMM: 133),
        ]),
        PaperSeriesData(id: "swedish", name: "Swedish SIS", sizes: [
            PaperSize(id: "sis-d0", name: "SIS D0", widthMM: 1091, heightMM: 1542),
            PaperSize(id: "sis-d1", name: "SIS D1", widthMM: 771, heightMM: 1091),
            PaperSize(id: "sis-d2", name: "SIS D2", widthMM: 545, heightMM: 771),
            PaperSize(id: "sis-d3", name: "SIS D3", widthMM: 386, heightMM: 545),
            PaperSize(id: "sis-d4", name: "SIS D4", widthMM: 273, heightMM: 386),
            PaperSize(id: "sis-e0", name: "SIS E0", widthMM: 878, heightMM: 1242),
            PaperSize(id: "sis-e1", name: "SIS E1", widthMM: 621, heightMM: 878),
            PaperSize(id: "sis-e2", name: "SIS E2", widthMM: 439, heightMM: 621),
            PaperSize(id: "sis-e3", name: "SIS E3", widthMM: 310, heightMM: 439),
            PaperSize(id: "sis-e4", name: "SIS E4", widthMM: 220, heightMM: 310),
        ]),
        PaperSeriesData(id: "french", name: "French Traditional", sizes: [
            PaperSize(id: "cloche", name: "Cloche", widthMM: 300, heightMM: 400),
            PaperSize(id: "pot-ecolier", name: "Pot, écolier", widthMM: 310, heightMM: 400),
            PaperSize(id: "telliere", name: "Tellière", widthMM: 340, heightMM: 440),
            PaperSize(id: "couronne-ecriture", name: "Couronne écriture", widthMM: 360, heightMM: 360),
            PaperSize(id: "couronne-edition", name: "Couronne édition", widthMM: 370, heightMM: 470),
            PaperSize(id: "raisin", name: "Raisin", widthMM: 500, heightMM: 650),
            PaperSize(id: "double-raisin", name: "Double Raisin", widthMM: 650, heightMM: 1000),
            PaperSize(id: "jesus", name: "Jésus", widthMM: 560, heightMM: 760),
            PaperSize(id: "soleil", name: "Soleil", widthMM: 600, heightMM: 800),
            PaperSize(id: "colombier-affiche", name: "Colombier affiche", widthMM: 600, heightMM: 800),
            PaperSize(id: "grand-aigle", name: "Grand Aigle", widthMM: 750, heightMM: 1050),
            PaperSize(id: "univers", name: "Univers", widthMM: 1000, heightMM: 1130),
        ]),
        PaperSeriesData(id: "imperial", name: "Imperial", sizes: [
            PaperSize(id: "antiquarian", name: "Antiquarian", widthMM: 787, heightMM: 1346),
            PaperSize(id: "atlas", name: "Atlas", widthMM: 660, heightMM: 864),
            PaperSize(id: "broadsheet", name: "Broadsheet", widthMM: 457, heightMM: 610),
            PaperSize(id: "crown", name: "Crown", widthMM: 381, heightMM: 508),
            PaperSize(id: "demy", name: "Demy", widthMM: 445, heightMM: 572),
            PaperSize(id: "double-demy", name: "Double Demy", widthMM: 572, heightMM: 902),
            PaperSize(id: "elephant", name: "Elephant", widthMM: 584, heightMM: 711),
            PaperSize(id: "emperor", name: "Emperor", widthMM: 1219, heightMM: 1829),
            PaperSize(id: "foolscap", name: "Foolscap", widthMM: 343, heightMM: 432),
            PaperSize(id: "imperial-p", name: "Imperial", widthMM: 559, heightMM: 762),
            PaperSize(id: "medium", name: "Medium", widthMM: 470, heightMM: 584),
            PaperSize(id: "royal", name: "Royal", widthMM: 508, heightMM: 635),
        ]),
    ]
}

public struct PaperPick: Sendable {
    public init(series: String, size: PaperSize) {
        (self.series, self.size) = (series, size)
    }

    public let series: String
    public let size: PaperSize

    public var key: String { "\(series)/\(size.id)" }

    public static let all: [PaperPick] = PaperSizeDatabase.allSeries.flatMap { series in series.sizes.map { PaperPick(series: series.id, size: $0) } }

    public static func named(_ id: String) -> PaperPick? { all.first { $0.size.id.lowercased() == id.lowercased() } }
}

public enum PaperUnit: Int, CaseIterable, Sendable {
    case mm, inches, fraction, points, pixels

    public static let dpis: [Double] = [72, 150, 300, 600]

    public var label: String { ["mm", "in", "in ½", "pt", "px"][rawValue] }

    public func text(_ size: PaperSize, dpi: Double) -> String {
        switch self {
        case .mm: return size.mmString
        case .inches: return "\(Self.decimal(size.widthInches)) × \(Self.decimal(size.heightInches)) in"
        case .fraction:
            let (width, height) = (Self.eighths(size.widthInches), Self.eighths(size.heightInches))
            return (width.exact && height.exact ? "" : "≈ ") + "\(width.text) × \(height.text)″"
        case .points: return size.pointsString
        case .pixels: return "\(Self.pixels(size.widthMM, dpi)) × \(Self.pixels(size.heightMM, dpi)) px"
        }
    }

    public static func pixels(_ mm: Double, _ dpi: Double) -> Int { Int((mm / 25.4 * dpi).rounded()) }

    public static func decimal(_ value: Double) -> String {
        var text = String(format: "%.2f", value)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text
    }

    /// exact: within 0.01 in
    public static func eighths(_ inches: Double) -> (text: String, exact: Bool) {
        let rounded = (inches * 8).rounded() / 8
        let whole = Int(rounded)
        let glyph = ["", "⅛", "¼", "⅜", "½", "⅝", "¾", "⅞"][Int(((rounded - Double(whole)) * 8).rounded()) % 8]
        let text = whole == 0 && !glyph.isEmpty ? glyph : "\(whole)\(glyph)"
        return (text, abs(rounded - inches) < 0.01)
    }
}

public enum PaperQuery: Equatable, Sendable {
    case none
    case name(String)
    /// millimetres
    case size(width: Double, height: Double, dpi: Double?)

    nonisolated(unsafe) private static let pixelPattern = try? Regex(#"^(\d+)\s*[x×]\s*(\d+)\s*@?\s*(\d+)\s*dpi$"#)
    nonisolated(unsafe) private static let sizePattern = try? Regex(#"^([\d.,]+)\s*[x×]\s*([\d.,]+)\s*(mm|in|"|″)?$"#)

    /// small bare numbers: inches
    public static func parse(_ text: String) -> PaperQuery {
        let query = text.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return .none }
        if let match = try? pixelPattern?.wholeMatch(in: query),
           let w = Double(match.output[1].substring ?? ""), let h = Double(match.output[2].substring ?? ""),
           let dpi = Double(match.output[3].substring ?? ""), dpi > 0 {
            return .size(width: w / dpi * 25.4, height: h / dpi * 25.4, dpi: dpi)
        }
        if let match = try? sizePattern?.wholeMatch(in: query),
           let w = Double((match.output[1].substring ?? "").replacingOccurrences(of: ",", with: ".")),
           let h = Double((match.output[2].substring ?? "").replacingOccurrences(of: ",", with: ".")) {
            let unit = match.output[3].substring.map(String.init)
            let inches = unit == "in" || unit == "\"" || unit == "″" || (unit == nil && w < 50 && h < 50)
            return inches ? .size(width: w * 25.4, height: h * 25.4, dpi: nil) : .size(width: w, height: h, dpi: nil)
        }
        return .name(query)
    }

    /// corner distance, either way
    public static func closest(width: Double, height: Double, limit: Int = 5) -> [(pick: PaperPick, dw: Double, dh: Double)] {
        PaperPick.all.map { pick -> (PaperPick, Double, Double, Double) in
            let (w, h) = (pick.size.widthMM, pick.size.heightMM)
            let upright = hypot(w - width, h - height)
            let turned = hypot(w - height, h - width)
            return turned < upright ? (pick, turned, w - height, h - width) : (pick, upright, w - width, h - height)
        }
        .sorted { $0.1 < $1.1 }
        .prefix(limit)
        .map { ($0.0, $0.2, $0.3) }
    }

    public func matches(_ pick: PaperPick) -> Bool {
        guard case .name(let query) = self else { return true }
        return pick.size.name.lowercased().contains(query) || pick.size.id.lowercased().contains(query)
            || pick.series.lowercased().contains(query)
    }

    #if DEBUG
    public static func selfCheck() {
        assert(parse("  ") == .none)
        assert(parse("A4") == .name("a4"))
        assert(parse("210x297") == .size(width: 210, height: 297, dpi: nil))
        assert(parse("8,5 × 11") == .size(width: 8.5 * 25.4, height: 11 * 25.4, dpi: nil))
        if case .size(let w, _, let dpi) = parse("2480x3508 @300dpi") { assert(abs(w - 209.97) < 0.01 && dpi == 300) } else { assert(false) }
        assert(closest(width: 297, height: 210).first?.pick.size.id == "A4")
        assert(PaperUnit.eighths(8.5) == ("8½", true) && PaperUnit.eighths(8.27) == ("8¼", false) && PaperUnit.eighths(0.375) == ("⅜", true))
        assert(PaperUnit.decimal(11.0) == "11" && PaperUnit.decimal(8.268) == "8.27")
        assert(closest(width: 215.9, height: 279.4).first?.pick.size.name == "Letter" && closest(width: 216, height: 279).first?.pick.size.name == "ANSI A")
    }
    #endif
}
