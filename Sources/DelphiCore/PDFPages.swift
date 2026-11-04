import CoreGraphics
import Foundation

public nonisolated enum PDFPagesEngine {
    public enum FitMode: String, CaseIterable, Sendable {
        case contain, cover, stretch
    }

    public enum PageOrientation: String, CaseIterable, Sendable {
        case auto, portrait, landscape
    }

    public enum RangeError: Error, Equatable, Sendable {
        case empty, malformed(String)
        /// "4-": the start page
        case openEnded(Int)
        /// page, page count
        case outOfRange(Int, Int)
    }

    public static let pxToPoints = 72.0 / 96.0
    public static let mmToPoints = 72.0 / 25.4

    /// 1-based inclusive spec, 0-based groups. "5-3" counts down.
    public static func parsePageRanges(_ spec: String, pageCount: Int) throws(RangeError) -> [[Int]] {
        var groups: [[Int]] = []
        for part in spec.split(separator: ",", omittingEmptySubsequences: false) {
            let trimmed = part.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { throw .empty }
            if let open = trimmed.wholeMatch(of: /(\d+)\s*-/), let start = Int(open.1) { throw .openEnded(start) }
            guard let match = trimmed.wholeMatch(of: /(\d+)(?:\s*-\s*(\d+))?/),
                  let lo = Int(match.1),
                  let hi = match.2.map({ Int($0) }) ?? lo
            else { throw .malformed(trimmed) }
            if min(lo, hi) < 1 { throw .outOfRange(min(lo, hi), pageCount) }
            if max(lo, hi) > pageCount { throw .outOfRange(max(lo, hi), pageCount) }
            groups.append(Array(stride(from: lo - 1, through: hi - 1, by: hi < lo ? -1 : 1)))
        }
        if groups.isEmpty { throw .empty }
        return groups
    }

    public static func everyPageAlone(_ pageCount: Int) -> [[Int]] {
        (0..<max(0, pageCount)).map { [$0] }
    }

    public static func normaliseRotation(_ degrees: Int) -> Int {
        let snapped = Int((Double(degrees) / 90).rounded()) * 90
        return ((snapped % 360) + 360) % 360
    }

    /// `scale` lowered until `size` renders within `maxPixels`.
    public static func cappedScale(_ scale: Double, size: CGSize, maxPixels: Double) -> Double {
        let area = size.width * size.height
        guard area > 0, scale > 0 else { return scale }
        return min(scale, (maxPixels / area).squareRoot())
    }

    public static func fitPlacement(imageSize: CGSize, area: CGSize, mode: FitMode) -> CGRect {
        if mode == .stretch { return CGRect(origin: .zero, size: area) }
        let scale = mode == .cover
            ? max(area.width / imageSize.width, area.height / imageSize.height)
            : min(area.width / imageSize.width, area.height / imageSize.height)
        let width = imageSize.width * scale
        let height = imageSize.height * scale
        return CGRect(x: (area.width - width) / 2, y: (area.height - height) / 2, width: width, height: height)
    }

    /// `paperMm` nil matches the image at 96 px per inch plus margins.
    public static func pageSetup(paperMm: CGSize?, orientation: PageOrientation, imageSize: CGSize, marginPt: Double) -> CGSize {
        guard let paperMm else {
            return CGSize(width: imageSize.width * pxToPoints + marginPt * 2, height: imageSize.height * pxToPoints + marginPt * 2)
        }
        let landscape = orientation == .landscape || (orientation == .auto && imageSize.width > imageSize.height)
        let long = max(paperMm.width, paperMm.height) * mmToPoints
        let short = min(paperMm.width, paperMm.height) * mmToPoints
        return landscape ? CGSize(width: long, height: short) : CGSize(width: short, height: long)
    }

    #if DEBUG
    public static func selfCheck() {
        assert((try? parsePageRanges("1-3, 5", pageCount: 10)) == [[0, 1, 2], [4]])
        assert((try? parsePageRanges(" 4 - 6 ,8 ", pageCount: 10)) == [[3, 4, 5], [7]])
        assert((try? parsePageRanges("5-3, 7", pageCount: 10)) == [[4, 3, 2], [6]])
        func failure(_ spec: String) -> RangeError? {
            do { _ = try parsePageRanges(spec, pageCount: 10); return nil } catch { return error }
        }
        assert(failure("4-") == .openEnded(4) && failure("4 -") == .openEnded(4))
        assert(failure("2-12") == .outOfRange(12, 10) && failure("0-2") == .outOfRange(0, 10) && failure("-4") == .malformed("-4"))
        assert(failure("") == .empty && failure("1,,2") == .empty && failure("a-b") == .malformed("a-b"))
        assert(everyPageAlone(3) == [[0], [1], [2]] && everyPageAlone(0).isEmpty)
        assert(normaliseRotation(450) == 90 && normaliseRotation(-90) == 270 && normaliseRotation(44) == 0)
        assert(fitPlacement(imageSize: CGSize(width: 200, height: 100), area: CGSize(width: 100, height: 100), mode: .contain)
               == CGRect(x: 0, y: 25, width: 100, height: 50))
        assert(fitPlacement(imageSize: CGSize(width: 200, height: 100), area: CGSize(width: 100, height: 100), mode: .cover)
               == CGRect(x: -50, y: 0, width: 200, height: 100))
        let a4 = pageSetup(paperMm: CGSize(width: 210, height: 297), orientation: .auto, imageSize: CGSize(width: 200, height: 100), marginPt: 0)
        assert(a4.width > a4.height)
        assert(cappedScale(2, size: CGSize(width: 100, height: 100), maxPixels: 1_000_000) == 2)
        assert(cappedScale(300.0 / 72, size: CGSize(width: 5000, height: 5000), maxPixels: 40_000_000) == (1.6).squareRoot())
    }
    #endif
}

/// Display space: the page as viewed, rotation applied, top-left origin, points. Page space: PDF user space, bottom-left origin.
public nonisolated enum PDFCropEngine {
    public struct Insets: Equatable, Sendable {
        public var left, top, right, bottom: Double

        public init(left: Double = 0, top: Double = 0, right: Double = 0, bottom: Double = 0) {
            (self.left, self.top, self.right, self.bottom) = (left, top, right, bottom)
        }
    }

    public static func displaySize(box: CGRect, rotation: Int) -> CGSize {
        rotation % 180 == 0 ? box.size : CGSize(width: box.height, height: box.width)
    }

    public static func boxFromPoints(_ a: CGPoint, _ b: CGPoint) -> CGRect {
        CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
    }

    // pdf boxes require area
    public static func intersectBox(_ a: CGRect, _ b: CGRect) -> CGRect? {
        let overlap = a.intersection(b)
        return overlap.isNull || overlap.width <= 0 || overlap.height <= 0 ? nil : overlap
    }

    public static func cropFromInsets(_ size: CGSize, _ insets: Insets) -> CGRect? {
        guard insets.left >= 0, insets.top >= 0, insets.right >= 0, insets.bottom >= 0 else { return nil }
        let width = size.width - insets.left - insets.right
        let height = size.height - insets.top - insets.bottom
        guard width > 0, height > 0 else { return nil }
        return CGRect(x: insets.left, y: insets.top, width: width, height: height)
    }

    public static func insets(from rect: CGRect, in size: CGSize) -> Insets {
        Insets(left: rect.minX, top: rect.minY, right: size.width - rect.maxX, bottom: size.height - rect.maxY)
    }

    /// Centred; callers clip overflow.
    public static func cropToPaper(_ size: CGSize, paper: CGSize) -> CGRect {
        CGRect(x: (size.width - paper.width) / 2, y: (size.height - paper.height) / 2, width: paper.width, height: paper.height)
    }

    public static func toPage(_ point: CGPoint, box: CGRect, rotation: Int) -> CGPoint {
        let (w, h) = (box.width, box.height)
        let local: CGPoint = switch rotation {
        case 90: CGPoint(x: point.y, y: point.x)
        case 180: CGPoint(x: w - point.x, y: point.y)
        case 270: CGPoint(x: w - point.y, y: h - point.x)
        default: CGPoint(x: point.x, y: h - point.y)
        }
        return CGPoint(x: local.x + box.minX, y: local.y + box.minY)
    }

    public static func toDisplay(_ point: CGPoint, box: CGRect, rotation: Int) -> CGPoint {
        let (w, h) = (box.width, box.height)
        let (u, v) = (point.x - box.minX, point.y - box.minY)
        return switch rotation {
        case 90: CGPoint(x: v, y: u)
        case 180: CGPoint(x: w - u, y: v)
        case 270: CGPoint(x: h - v, y: w - u)
        default: CGPoint(x: u, y: h - v)
        }
    }

    public static func toPage(_ rect: CGRect, box: CGRect, rotation: Int) -> CGRect {
        boxFromPoints(toPage(CGPoint(x: rect.minX, y: rect.minY), box: box, rotation: rotation),
                      toPage(CGPoint(x: rect.maxX, y: rect.maxY), box: box, rotation: rotation))
    }

    public static func toDisplay(_ rect: CGRect, box: CGRect, rotation: Int) -> CGRect {
        boxFromPoints(toDisplay(CGPoint(x: rect.minX, y: rect.minY), box: box, rotation: rotation),
                      toDisplay(CGPoint(x: rect.maxX, y: rect.maxY), box: box, rotation: rotation))
    }

    #if DEBUG
    public static func selfCheck() {
        let bounds = CGSize(width: 200, height: 300)
        assert(intersectBox(CGRect(x: 0, y: 0, width: 100, height: 100), CGRect(x: 50, y: 50, width: 100, height: 100))
               == CGRect(x: 50, y: 50, width: 50, height: 50))
        assert(intersectBox(CGRect(x: 0, y: 0, width: 50, height: 50), CGRect(x: 50, y: 0, width: 50, height: 50)) == nil)
        assert(cropFromInsets(bounds, Insets(left: 10, top: 20, right: 30, bottom: 40)) == CGRect(x: 10, y: 20, width: 160, height: 240))
        assert(cropFromInsets(bounds, Insets(left: 100, right: 100)) == nil && cropFromInsets(bounds, Insets(left: -1)) == nil)
        assert(insets(from: CGRect(x: 10, y: 20, width: 160, height: 240), in: bounds) == Insets(left: 10, top: 20, right: 30, bottom: 40))
        assert(cropToPaper(bounds, paper: CGSize(width: 100, height: 200)) == CGRect(x: 50, y: 50, width: 100, height: 200))
        let box = CGRect(x: 10, y: 20, width: 200, height: 300)
        for rotation in [0, 90, 180, 270] {
            let size = displaySize(box: box, rotation: rotation)
            let rect = CGRect(x: 5, y: 15, width: size.width / 2, height: size.height / 4)
            let page = toPage(rect, box: box, rotation: rotation)
            assert(box.contains(page) && toDisplay(page, box: box, rotation: rotation) == rect)
        }
    }
    #endif
}

public nonisolated enum PDFStampEngine {
    public enum Anchor: String, CaseIterable, Sendable {
        case topLeft, topCenter, topRight
        case middleLeft, middleCenter, middleRight
        case bottomLeft, bottomCenter, bottomRight

        public var row: Int { Self.allCases.firstIndex(of: self)! / 3 }
        public var column: Int { Self.allCases.firstIndex(of: self)! % 3 }

        public var systemImage: String {
            ["arrow.up.left", "arrow.up", "arrow.up.right", "arrow.left", "circle.fill", "arrow.right",
             "arrow.down.left", "arrow.down", "arrow.down.right"][Self.allCases.firstIndex(of: self)!]
        }

        public var label: String {
            switch self {
            case .topLeft: String(localized: "Top left")
            case .topCenter: String(localized: "Top centre")
            case .topRight: String(localized: "Top right")
            case .middleLeft: String(localized: "Middle left")
            case .middleCenter: String(localized: "Centre")
            case .middleRight: String(localized: "Middle right")
            case .bottomLeft: String(localized: "Bottom left")
            case .bottomCenter: String(localized: "Bottom centre")
            case .bottomRight: String(localized: "Bottom right")
            }
        }
    }

    public enum NumeralStyle: String, CaseIterable, Sendable {
        case arabic, romanLower, romanUpper, alphaLower, alphaUpper

        public var label: String {
            ["1, 2, 3", "i, ii, iii", "I, II, III", "a, b, c", "A, B, C"][Self.allCases.firstIndex(of: self)!]
        }
    }

    public enum FontFamily: String, CaseIterable, Sendable {
        case sans, serif, mono

        public var postScriptName: String {
            switch self {
            case .sans: "Helvetica"
            case .serif: "TimesNewRomanPSMT"
            case .mono: "Courier"
            }
        }
    }

    public enum StampMode: String, CaseIterable, Sendable {
        case label, watermark
    }

    public struct NumberSection: Identifiable, Equatable, Sendable {
        public let id = UUID()
        public var fromPage: Int
        public var style: NumeralStyle
        public var startAt: Int

        public init(fromPage: Int = 1, style: NumeralStyle = .arabic, startAt: Int = 1) {
            (self.fromPage, self.style, self.startAt) = (fromPage, style, startAt)
        }
    }

    public struct Options: Equatable, Sendable {
        public var numbersOn = true
        public var template = "{n} / {N}"
        public var numberAnchor = Anchor.bottomCenter
        public var font = FontFamily.sans
        public var fontSize = 11.0
        public var margin = 24.0
        public var stampOn = false
        public var stampText = ""
        public var stampAnchor = Anchor.topRight
        public var stampMode = StampMode.label
        public var watermarkOpacity = 0.15
        public var sections = [NumberSection()]

        public init() {}
    }

    /// Bottom-left origin; `y` is the baseline.
    public static func placeText(page: CGSize, textWidth: Double, fontSize: Double, anchor: Anchor, margin: Double) -> CGPoint {
        let x: Double = switch anchor.column {
        case 0: margin
        case 2: page.width - textWidth - margin
        default: (page.width - textWidth) / 2
        }
        let y: Double = switch anchor.row {
        case 0: page.height - margin - fontSize
        case 2: margin
        default: (page.height - fontSize) / 2
        }
        return CGPoint(x: x, y: y)
    }

    public static func expandNumber(_ template: String, n: String, total: String) -> String {
        template.replacingOccurrences(of: "{n}", with: n).replacingOccurrences(of: "{N}", with: total)
    }

    // helvetica caps ~0.55em
    public static func watermarkSize(page: CGSize, textLength: Int) -> Double {
        let raw = 0.8 * hypot(page.width, page.height) / (0.55 * Double(max(1, textLength)))
        return min(raw, min(page.width, page.height) * 0.9)
    }

    public static func formatNumeral(_ value: Int, style: NumeralStyle) -> String {
        switch style {
        case .arabic: String(value)
        case .romanLower: roman(value).lowercased()
        case .romanUpper: roman(value)
        case .alphaLower: alpha(value)
        case .alphaUpper: alpha(value).uppercased()
        }
    }

    /// `fromPage` is clamped into the document, so a section past the end numbers the last page.
    public static func resolvePageNumbers(_ sections: [NumberSection], pageCount: Int) -> [String?] {
        guard pageCount > 0 else { return [] }
        let ordered = sections.map { (from: min(max(1, $0.fromPage), pageCount), section: $0) }.sorted { $0.from < $1.from }
        return (1...pageCount).map { page in
            guard let active = ordered.last(where: { $0.from <= page }) else { return nil }
            // typed startAt may overflow
            return formatNumeral(active.section.startAt &+ (page - active.from), style: active.section.style)
        }
    }

    /// The section that numbers a 1-based page; nil before the first one starts.
    public static func resolveSection(_ sections: [NumberSection], page: Int) -> NumberSection? {
        sections.filter { $0.fromPage <= page }.max { $0.fromPage < $1.fromPage }
    }

    private static let romanTable: [(Int, String)] = [
        (1000, "M"), (900, "CM"), (500, "D"), (400, "CD"), (100, "C"), (90, "XC"),
        (50, "L"), (40, "XL"), (10, "X"), (9, "IX"), (5, "V"), (4, "IV"), (1, "I"),
    ]

    private static func roman(_ value: Int) -> String {
        guard value > 0, value < 4000 else { return String(value) }
        var n = value
        var out = ""
        for (amount, symbol) in romanTable {
            while n >= amount {
                out += symbol
                n -= amount
            }
        }
        return out
    }

    private static func alpha(_ value: Int) -> String {
        guard value > 0 else { return String(value) }
        var n = value
        var out = ""
        while n > 0 {
            out = String(UnicodeScalar(UInt8(97 + (n - 1) % 26))) + out
            n = (n - 1) / 26
        }
        return out
    }

    #if DEBUG
    public static func selfCheck() {
        let page = CGSize(width: 600, height: 800)
        assert(placeText(page: page, textWidth: 100, fontSize: 12, anchor: .topLeft, margin: 20) == CGPoint(x: 20, y: 768))
        assert(placeText(page: page, textWidth: 100, fontSize: 12, anchor: .bottomRight, margin: 20) == CGPoint(x: 480, y: 20))
        assert(placeText(page: page, textWidth: 100, fontSize: 12, anchor: .middleCenter, margin: 20) == CGPoint(x: 250, y: 394))
        assert(expandNumber("Page {n} of {N}, {n}", n: "3", total: "9") == "Page 3 of 9, 3")
        assert(formatNumeral(4, style: .romanLower) == "iv" && formatNumeral(14, style: .romanUpper) == "XIV")
        assert(formatNumeral(1, style: .alphaLower) == "a" && formatNumeral(27, style: .alphaLower) == "aa" && formatNumeral(28, style: .alphaUpper) == "AB")
        assert(formatNumeral(0, style: .romanUpper) == "0" && formatNumeral(4000, style: .romanLower) == "4000" && formatNumeral(0, style: .alphaLower) == "0")
        let sections = [NumberSection(fromPage: 3), NumberSection(fromPage: 2, style: .romanLower)]
        assert(resolvePageNumbers(sections, pageCount: 4) == [nil, "i", "1", "2"])
        assert(resolvePageNumbers([NumberSection(startAt: 5)], pageCount: 2) == ["5", "6"])
        assert(resolvePageNumbers(sections, pageCount: 0).isEmpty)
        assert(resolveSection(sections, page: 1) == nil && resolveSection(sections, page: 2)?.style == .romanLower)
        assert(resolveSection(sections, page: 9)?.style == .arabic)
        assert(resolvePageNumbers([NumberSection(fromPage: 99)], pageCount: 3) == [nil, nil, "1"])
        assert(resolvePageNumbers([NumberSection(fromPage: .min)], pageCount: 2) == ["1", "2"])
        assert(resolvePageNumbers([NumberSection(startAt: .max)], pageCount: 2).count == 2)
        assert(Anchor.bottomCenter.row == 2 && Anchor.bottomCenter.column == 1 && Anchor.middleCenter.systemImage == "circle.fill")
    }
    #endif
}

public nonisolated enum ImageToPDFLayout {
    public struct Options: Sendable {
        /// nil matches each image
        public var paperMm: CGSize?
        public var orientation: PDFPagesEngine.PageOrientation
        public var fit: PDFPagesEngine.FitMode
        public var marginMm: Double

        public init(paperMm: CGSize? = nil, orientation: PDFPagesEngine.PageOrientation = .auto, fit: PDFPagesEngine.FitMode = .contain, marginMm: Double = 0) {
            (self.paperMm, self.orientation, self.fit, self.marginMm) = (paperMm, orientation, fit, marginMm)
        }
    }

    /// PDF points, bottom-left origin: the page, the area inside the margins, and the image's placement.
    public static func layout(imageSize: CGSize, options: Options) -> (page: CGSize, area: CGRect, placement: CGRect)? {
        let margin = options.marginMm * PDFPagesEngine.mmToPoints
        let page = PDFPagesEngine.pageSetup(paperMm: options.paperMm, orientation: options.orientation, imageSize: imageSize, marginPt: margin)
        // CGRect.width hides negative sizes
        let inner = CGSize(width: page.width - margin * 2, height: page.height - margin * 2)
        guard imageSize.width > 0, imageSize.height > 0, inner.width > 0, inner.height > 0 else { return nil }
        let placement = PDFPagesEngine.fitPlacement(imageSize: imageSize, area: inner, mode: options.paperMm == nil ? .contain : options.fit)
        return (page, CGRect(origin: CGPoint(x: margin, y: margin), size: inner), placement.offsetBy(dx: margin, dy: margin))
    }

    /// Finder order: "page2" before "page10".
    public static func sortedByName(_ names: [String], ascending: Bool) -> [Int] {
        names.indices.sorted {
            let order = names[$0].localizedStandardCompare(names[$1])
            return ascending ? order == .orderedAscending : order == .orderedDescending
        }
    }

    #if DEBUG
    public static func selfCheck() {
        let names = ["page10.png", "Page2.png", "page1.png", "cover.jpg"]
        assert(sortedByName(names, ascending: true).map { names[$0] } == ["cover.jpg", "page1.png", "Page2.png", "page10.png"])
        assert(sortedByName(names, ascending: false).map { names[$0] } == ["page10.png", "Page2.png", "page1.png", "cover.jpg"])
        let layout = layout(imageSize: CGSize(width: 4000, height: 3000), options: Options(paperMm: CGSize(width: 210, height: 297), marginMm: 10))!
        assert(layout.page.width > layout.page.height && layout.area.minX > 28 && layout.area.contains(layout.placement))
        assert(self.layout(imageSize: .zero, options: Options()) == nil)
    }
    #endif
}
