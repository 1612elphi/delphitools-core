import CoreImage

// MARK: - EAN-13

public enum EAN13: Sendable {
    private static let lPatterns: [[Int]] = [
        [0,0,0,1,1,0,1], [0,0,1,1,0,0,1], [0,0,1,0,0,1,1], [0,1,1,1,1,0,1],
        [0,1,0,0,0,1,1], [0,1,1,0,0,0,1], [0,1,0,1,1,1,1], [0,1,1,1,0,1,1],
        [0,1,1,0,1,1,1], [0,0,0,1,0,1,1],
    ]
    private static let gPatterns: [[Int]] = [
        [0,1,0,0,1,1,1], [0,1,1,0,0,1,1], [0,0,1,1,0,1,1], [0,1,0,0,0,0,1],
        [0,0,1,1,1,0,1], [0,0,0,0,1,0,1], [0,0,1,0,0,0,1], [0,0,0,0,1,0,1],
        [0,0,0,1,0,0,1], [0,0,1,0,1,1,1],
    ]
    private static let rPatterns: [[Int]] = [
        [1,1,1,0,0,1,0], [1,1,0,0,1,1,0], [1,1,0,1,1,0,0], [1,0,0,0,0,1,0],
        [1,0,1,1,1,0,0], [1,0,0,1,1,1,0], [1,0,1,0,0,0,0], [1,0,0,0,1,0,0],
        [1,0,0,1,0,0,0], [1,1,1,0,1,0,0],
    ]
    private static let parityPatterns: [[Character]] = [
        ["L","L","L","L","L","L"], ["L","L","G","L","G","G"],
        ["L","L","G","G","L","G"], ["L","L","G","G","G","L"],
        ["L","G","L","L","G","G"], ["L","G","G","L","L","G"],
        ["L","G","G","G","L","L"], ["L","G","L","G","L","G"],
        ["L","G","L","G","G","L"], ["L","G","G","L","G","L"],
    ]

    /// Check digit for the first 12 digits, weights 1 and 3.
    public static func checkDigit(_ first12: [Int]) -> Int {
        let checkSum = (0..<12).reduce(0) { $0 + first12[$1] * ($1 % 2 == 0 ? 1 : 3) }
        return (10 - (checkSum % 10)) % 10
    }

    /// The 95 modules, 1 for a bar; nil unless `digits` is 13 digits with a valid check digit.
    public static func bars(_ digits: String) -> [Int]? {
        let chars = Array(digits)
        let d = chars.compactMap { $0.isASCII ? $0.wholeNumberValue : nil }
        guard chars.count == 13, d.count == 13 else { return nil }
        guard d[12] == checkDigit(d) else { return nil }

        var bars: [Int] = [1, 0, 1]
        let parity = parityPatterns[d[0]]
        for i in 0..<6 {
            let digit = d[i + 1]
            bars += parity[i] == "L" ? lPatterns[digit] : gPatterns[digit]
        }
        bars += [0, 1, 0, 1, 0]
        for i in 0..<6 {
            bars += rPatterns[d[i + 7]]
        }
        bars += [1, 0, 1]
        return bars
    }

    /// Modules of the start, centre and end guards, which run longer than the digit bars.
    public static let guards: Set<Int> = [0, 1, 2, 45, 46, 47, 48, 49, 92, 93, 94]

}

// MARK: - View Model

@MainActor
public final class BarcodeGeneratorViewModel {
    public enum BarcodeType: String, CaseIterable, Identifiable, Sendable {
        case code128 = "Code 128"
        case pdf417 = "PDF417"
        case aztec = "Aztec"
        case ean13 = "EAN-13"

        public var id: String { rawValue }

        public var label: String {
            switch self {
            case .code128: return String(localized: "Code 128")
            case .pdf417: return String(localized: "PDF417")
            case .aztec: return String(localized: "Aztec")
            case .ean13: return String(localized: "EAN-13")
            }
        }

        public var ciFilterName: String? {
            switch self {
            case .code128: return "CICode128BarcodeGenerator"
            case .pdf417: return "CIPDF417BarcodeGenerator"
            case .aztec: return "CIAztecCodeGenerator"
            case .ean13: return nil
            }
        }

        public var description: String {
            switch self {
            case .code128: return String(localized: "Alphanumeric, variable length. Used in shipping and logistics.")
            case .pdf417: return String(localized: "High-capacity 2D barcode. Used in IDs, boarding passes, and labels.")
            case .aztec: return String(localized: "Compact 2D barcode. Used in transport tickets and boarding passes.")
            case .ean13: return String(localized: "13-digit numeric. Standard retail product barcode.")
            }
        }

        public var placeholder: String {
            switch self {
            case .code128: return "Hello World"
            case .pdf417: return "Enter text or data"
            case .aztec: return "Enter text or URL"
            case .ean13: return "5901234123457"
            }
        }

        /// 1D symbologies carry a human-readable text line (web: `includetext`).
        public var is1D: Bool {
            self == .code128 || self == .ean13
        }
    }

    public var content = ""
    public var barcodeType: BarcodeType = .code128

    public init() {}

    private let ciContext = CIContext()
}

// MARK: - Modules

extension BarcodeGeneratorViewModel {
    public enum Modules: Sendable {
        case empty
        /// Rows of modules, the height of one row in modules, and the human-readable text.
        case code([[Bool]], rowHeight: Int, text: String)
        case failure(String)
    }

    /// The code for the current content as modules, for drawing at any size. EAN-13 takes 12 digits and adds the check digit.
    public func modules() -> Modules {
        guard !content.isEmpty else { return .empty }
        if barcodeType == .ean13 {
            var digits = content.trimmingCharacters(in: .whitespaces)
            guard (12...13).contains(digits.count), digits.allSatisfy({ $0.isASCII && $0.isWholeNumber }) else {
                return .failure("EAN-13 requires exactly 13 digits with a valid check digit.")
            }
            if digits.count == 12 {
                digits += String(EAN13.checkDigit(digits.compactMap(\.wholeNumberValue)))
            }
            guard let bars = EAN13.bars(digits) else {
                return .failure("Invalid EAN-13 code. Check the check digit.")
            }
            return .code([bars.map { $0 == 1 }], rowHeight: 1, text: digits)
        }
        guard let filterName = barcodeType.ciFilterName, let filter = CIFilter(name: filterName) else {
            return .failure("Filter not available.")
        }
        guard let data = content.data(using: .isoLatin1) ?? content.data(using: .ascii) else {
            return .failure("Invalid characters for this barcode type.")
        }
        filter.setValue(data, forKey: "inputMessage")
        guard let image = filter.outputImage,
              let found = BarcodeMatrixExtractor.modules(from: image, context: ciContext, centred: barcodeType == .aztec) else {
            return .failure("Could not generate barcode. Check the input format.")
        }
        return .code(found.rows, rowHeight: found.rowHeight, text: content)
    }
}

/// Reads a Core Image barcode bitmap back into modules: the margin cut away, one sample per module.
public enum BarcodeMatrixExtractor: Sendable {
    public static func modules(from image: CIImage, context: CIContext, centred: Bool) -> (rows: [[Bool]], rowHeight: Int)? {
        guard let cg = context.createCGImage(image, from: image.extent),
              let data = cg.dataProvider?.data, let bytes = CFDataGetBytePtr(data) else { return nil }
        let (width, height, bpp, bpr) = (cg.width, cg.height, cg.bitsPerPixel / 8, cg.bytesPerRow)
        let dark = (0..<height).map { y in (0..<width).map { x in bytes[y * bpr + x * bpp] < 128 } }
        return modules(from: dark, centred: centred)
    }

    /// `pixels` is dark per pixel. The narrowest run across and down is one module; a centred code (Aztec) keeps its middle,
    /// so the margin is cut evenly.
    public static func modules(from pixels: [[Bool]], centred: Bool) -> (rows: [[Bool]], rowHeight: Int)? {
        let height = pixels.count
        guard height > 0, let width = pixels.first?.count, width > 0 else { return nil }
        let darkRows = (0..<height).filter { pixels[$0].contains(true) }
        let darkColumns = (0..<width).filter { x in pixels.contains { $0[x] } }
        guard var top = darkRows.first, var bottom = darkRows.last, var left = darkColumns.first, var right = darkColumns.last else { return nil }
        if centred {
            let margin = min(top, height - 1 - bottom, left, width - 1 - right)
            (top, bottom, left, right) = (margin, height - 1 - margin, margin, width - 1 - margin)
        }
        let cropped = pixels[top...bottom].map { Array($0[left...right]) }
        func narrowest(_ lines: [[Bool]]) -> Int {
            var least = Int.max
            for line in lines {
                var run = 1
                for i in 1..<max(line.count, 1) {
                    if line[i] == line[i - 1] { run += 1 } else { least = min(least, run); run = 1 }
                }
                least = min(least, run)
            }
            return max(1, least)
        }
        let across = narrowest(cropped)
        let columns = cropped[0].indices.map { x in cropped.map { $0[x] } }
        let down = narrowest(columns)
        let rows = stride(from: down / 2, to: cropped.count, by: down).map { y in
            stride(from: across / 2, to: cropped[y].count, by: across).map { cropped[y][$0] }
        }
        return (rows, down / across)
    }
}

#if DEBUG
extension BarcodeMatrixExtractor {
    public static func selfCheck() {
        // 2×4-pixel modules, 1-pixel margin
        let rows = [[true, false, true], [false, true, true]]
        var pixels = [[Bool]](repeating: [Bool](repeating: false, count: 8), count: 10)
        for (r, row) in rows.enumerated() {
            for (c, dark) in row.enumerated() where dark {
                for y in 1 + r * 4..<5 + r * 4 { for x in 1 + c * 2..<3 + c * 2 { pixels[y][x] = true } }
            }
        }
        let found = modules(from: pixels, centred: false)
        assert(found?.rows == rows && found?.rowHeight == 2, "one sample per module")
        assert(EAN13.checkDigit([5, 9, 0, 1, 2, 3, 4, 1, 2, 3, 4, 5]) == 7)
        assert(EAN13.bars("5901234123457")?.count == 95 && EAN13.bars("5901234123458") == nil)
    }
}
#endif
