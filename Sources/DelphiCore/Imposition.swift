import CoreGraphics
import Foundation
import PDFKit


/// A single page placed on one side of a sheet.
public nonisolated struct ImpositionPlacement: Sendable {
    /// 1-indexed document page number. 0 means blank.
    public let pageNumber: Int
    /// X offset from sheet origin (mm), left edge.
    public let x: Double
    /// Y offset from sheet origin (mm), top edge.
    public let y: Double
    /// Width of the placed page area (mm).
    public let width: Double
    /// Height of the placed page area (mm).
    public let height: Double
    /// Rotation in degrees (0, 90, 180, 270).
    public let rotation: Int
    /// Which side of the physical sheet this placement belongs to.
    public let side: SheetSide
}

public nonisolated enum SheetSide: String, Sendable {
    case front, back
}

/// One physical sheet with placements on front and back.
public nonisolated struct SheetDefinition: Identifiable, Sendable {
    public let id: Int // sheetNumber
    public let front: [ImpositionPlacement]
    public let back: [ImpositionPlacement]
    /// 0-based signature index
    public var signature = 0
    public var sheetNumber: Int { id }
}

public nonisolated struct ImpositionResult: Sendable {
    public let sheets: [SheetDefinition]
    public var totalSheets: Int { sheets.count }
    /// Total document pages (after padding to signature multiple).
    public let totalPages: Int
    /// Number of pages from the source document actually placed.
    public let pagesUsed: Int
    /// Number of blank pages inserted to complete the final signature.
    public var blanksAdded: Int { max(0, totalPages - pagesUsed) }
}

/// How content is scaled to fit each cell.
public nonisolated enum ImpositionScaling: String, CaseIterable, Identifiable, Sendable {
    case fit = "Fit"
    case fill = "Fill"
    case actual = "Actual"
    public var id: String { rawValue }
}

/// Duplex flip direction.
public nonisolated enum DuplexFlip: String, CaseIterable, Identifiable, Sendable {
    case longEdge = "long-edge"
    case shortEdge = "short-edge"
    public var id: String { rawValue }
}

public nonisolated struct ImpositionConfig: Sendable {
    public var layoutId: ImpositionLayoutID
    public var paperWidthMm: Double
    public var paperHeightMm: Double
    public var orientation: ImpositionOrientation
    public var marginMm: Double
    public var gutterMm: Double
    public var creepMm: Double
    public var scaling: ImpositionScaling
    public var cropMarks: Bool
    public var nUp: Int
    public var customRows: Int
    public var customCols: Int
    public var duplexFlip: DuplexFlip
    /// multiple of 4
    public var signaturePages = 16

    public init(layoutId: ImpositionLayoutID = .saddleStitch, paperWidthMm: Double = 210, paperHeightMm: Double = 297,
                orientation: ImpositionOrientation = .landscape, marginMm: Double = 5, gutterMm: Double = 2, creepMm: Double = 0,
                scaling: ImpositionScaling = .fit, cropMarks: Bool = true, nUp: Int = 4, customRows: Int = 2, customCols: Int = 2,
                duplexFlip: DuplexFlip = .longEdge, signaturePages: Int = 16) {
        (self.layoutId, self.paperWidthMm, self.paperHeightMm, self.orientation) = (layoutId, paperWidthMm, paperHeightMm, orientation)
        (self.marginMm, self.gutterMm, self.creepMm, self.scaling, self.cropMarks) = (marginMm, gutterMm, creepMm, scaling, cropMarks)
        (self.nUp, self.customRows, self.customCols, self.duplexFlip, self.signaturePages) = (nUp, customRows, customCols, duplexFlip, signaturePages)
    }

    /// Effective sheet width after applying orientation.
    public var sheetW: Double {
        switch orientation {
        case .landscape: max(paperWidthMm, paperHeightMm)
        case .portrait: min(paperWidthMm, paperHeightMm)
        }
    }

    /// landscape long edge tumbles
    public var turnsTopOverBottom: Bool {
        duplexFlip == .longEdge ? sheetW > sheetH : sheetW <= sheetH
    }

    /// Effective sheet height after applying orientation.
    public var sheetH: Double {
        switch orientation {
        case .landscape: min(paperWidthMm, paperHeightMm)
        case .portrait: max(paperWidthMm, paperHeightMm)
        }
    }
}

public nonisolated enum ImpositionOrientation: String, CaseIterable, Identifiable, Sendable {
    case portrait, landscape
    public var id: String { rawValue }
}


public nonisolated enum ImpositionLayoutID: String, CaseIterable, Identifiable, Sendable {
    case saddleStitch = "saddle-stitch"
    case perfectBind = "perfect-bind"
    case stepAndRepeat = "step-and-repeat"
    case fourUpBooklet = "four-up-booklet"
    case gangRun = "gang-run"
    case customNUp = "custom-nup"

    public var id: String { rawValue }

    public var name: String {
        switch self {
        case .saddleStitch: "2-up Saddle Stitch"
        case .perfectBind: "2-up Perfect Bind"
        case .stepAndRepeat: "2-up Step & Repeat"
        case .fourUpBooklet: "4-up Booklet"
        case .gangRun: "N-up Gang Run"
        case .customNUp: "Custom N-up"
        }
    }

    /// Whether this layout supports duplex direction (has fold geometry).
    public var supportsDuplex: Bool {
        switch self {
        case .saddleStitch, .perfectBind, .fourUpBooklet: true
        default: false
        }
    }

    /// Whether this layout uses creep compensation.
    public var supportsCreep: Bool { self == .saddleStitch || self == .perfectBind }

    public func calculate(totalSourcePages: Int, config: ImpositionConfig) -> ImpositionResult {
        var result: ImpositionResult
        switch self {
        case .saddleStitch: result = ImpositionEngine.saddleStitch(totalSourcePages, config)
        case .perfectBind: result = ImpositionEngine.perfectBind(totalSourcePages, config)
        case .stepAndRepeat: result = ImpositionEngine.stepAndRepeat(totalSourcePages, config)
        case .fourUpBooklet: result = ImpositionEngine.fourUpBooklet(totalSourcePages, config)
        case .gangRun: result = ImpositionEngine.gangRun(totalSourcePages, config)
        case .customNUp: result = ImpositionEngine.customNUp(totalSourcePages, config)
        }
        // layouts assume book turn
        if supportsDuplex && config.turnsTopOverBottom {
            result = ImpositionEngine.turnBacks(result, config)
        }
        return result
    }
}


public nonisolated enum ImpositionEngine {

    public static let mmToPoints: Double = 72.0 / 25.4


    private static func padToMultiple(_ n: Int, _ multiple: Int) -> Int {
        let rem = n % multiple
        return rem == 0 ? n : n + (multiple - rem)
    }

    private static func pageOrBlank(_ p: Int, source: Int) -> Int {
        p <= source ? p : 0
    }

    /// Build a grid of placements for one side of a sheet.
    private static func buildGrid(
        pageNumbers: [Int],
        rows: Int, cols: Int,
        sheetW: Double, sheetH: Double,
        marginMm: Double, gutterMm: Double,
        side: SheetSide,
        rotations: [Int]? = nil
    ) -> [ImpositionPlacement] {
        let usableW = sheetW - marginMm * 2 - gutterMm * Double(cols - 1)
        let usableH = sheetH - marginMm * 2 - gutterMm * Double(rows - 1)
        let cellW = usableW / Double(cols)
        let cellH = usableH / Double(rows)

        return pageNumbers.enumerated().map { i, pageNum in
            let col = i % cols
            let row = i / cols
            let x = marginMm + Double(col) * (cellW + gutterMm)
            let y = marginMm + Double(row) * (cellH + gutterMm)
            return ImpositionPlacement(
                pageNumber: pageNum,
                x: x, y: y,
                width: cellW, height: cellH,
                rotation: rotations?[i] ?? 0,
                side: side
            )
        }
    }


    public static func turnBacks(_ result: ImpositionResult, _ config: ImpositionConfig) -> ImpositionResult {
        let (width, height) = (config.sheetW, config.sheetH)
        let sheets = result.sheets.map { sheet in
            let back = sheet.back.map { p in
                ImpositionPlacement(
                    pageNumber: p.pageNumber,
                    x: width - p.x - p.width, y: height - p.y - p.height,
                    width: p.width, height: p.height,
                    rotation: (p.rotation + 180) % 360,
                    side: p.side
                )
            }
            return SheetDefinition(id: sheet.id, front: sheet.front, back: back, signature: sheet.signature)
        }
        return ImpositionResult(sheets: sheets, totalPages: result.totalPages, pagesUsed: result.pagesUsed)
    }


    public static func saddleStitch(_ totalSourcePages: Int, _ config: ImpositionConfig) -> ImpositionResult {
        let totalPages = padToMultiple(max(totalSourcePages, 4), 4)
        let sheets = nestedSheets(pages: totalPages, from: 0, firstID: 1, signature: 0, source: totalSourcePages, config)
        return ImpositionResult(sheets: sheets, totalPages: totalPages, pagesUsed: totalSourcePages)
    }

    /// pages: multiple of 4
    private static func nestedSheets(pages totalPages: Int, from base: Int, firstID: Int, signature: Int,
                                     source totalSourcePages: Int, _ config: ImpositionConfig) -> [SheetDefinition] {
        let numSheets = totalPages / 4
        let sw = config.sheetW
        let sh = config.sheetH

        var sheets: [SheetDefinition] = []

        for s in 0..<numSheets {
            let rawCreep = Double(numSheets - 1 - s) * config.creepMm
            let creepOffset = min(rawCreep, config.marginMm)

            let frontLeft = base + totalPages - 2 * s
            let frontRight = base + 2 * s + 1
            let backLeft = base + 2 * s + 2
            let backRight = base + totalPages - 2 * s - 1

            let usableW = sw - config.marginMm * 2
            let usableH = sh - config.marginMm * 2
            let halfW = (usableW - config.gutterMm) / 2

            let front = [
                ImpositionPlacement(
                    pageNumber: pageOrBlank(frontLeft, source: totalSourcePages),
                    x: config.marginMm - creepOffset, y: config.marginMm,
                    width: halfW, height: usableH, rotation: 0, side: .front),
                ImpositionPlacement(
                    pageNumber: pageOrBlank(frontRight, source: totalSourcePages),
                    x: config.marginMm + halfW + config.gutterMm + creepOffset, y: config.marginMm,
                    width: halfW, height: usableH, rotation: 0, side: .front),
            ]

            let back = [
                ImpositionPlacement(
                    pageNumber: pageOrBlank(backLeft, source: totalSourcePages),
                    x: config.marginMm - creepOffset, y: config.marginMm,
                    width: halfW, height: usableH, rotation: 0, side: .back),
                ImpositionPlacement(
                    pageNumber: pageOrBlank(backRight, source: totalSourcePages),
                    x: config.marginMm + halfW + config.gutterMm + creepOffset, y: config.marginMm,
                    width: halfW, height: usableH, rotation: 0, side: .back),
            ]

            sheets.append(SheetDefinition(id: firstID + s, front: front, back: back, signature: signature))
        }
        return sheets
    }


    public static func perfectBind(_ totalSourcePages: Int, _ config: ImpositionConfig) -> ImpositionResult {
        let size = padToMultiple(max(4, config.signaturePages), 4)
        let totalPages = padToMultiple(max(totalSourcePages, 1), size)
        var sheets: [SheetDefinition] = []
        for base in stride(from: 0, to: totalPages, by: size) {
            sheets += nestedSheets(pages: size, from: base, firstID: sheets.count + 1, signature: base / size,
                                   source: totalSourcePages, config)
        }
        return ImpositionResult(sheets: sheets, totalPages: totalPages, pagesUsed: totalSourcePages)
    }


    public static func stepAndRepeat(_ totalSourcePages: Int, _ config: ImpositionConfig) -> ImpositionResult {
        let sw = config.sheetW
        let sh = config.sheetH
        let sourcePage = totalSourcePages >= 1 ? 1 : 0
        let backPage = totalSourcePages >= 2 ? 2 : sourcePage

        let sheet = SheetDefinition(
            id: 1,
            front: buildGrid(pageNumbers: [sourcePage, sourcePage], rows: 1, cols: 2,
                             sheetW: sw, sheetH: sh,
                             marginMm: config.marginMm, gutterMm: config.gutterMm,
                             side: .front),
            back: buildGrid(pageNumbers: [backPage, backPage], rows: 1, cols: 2,
                            sheetW: sw, sheetH: sh,
                            marginMm: config.marginMm, gutterMm: config.gutterMm,
                            side: .back)
        )

        return ImpositionResult(sheets: [sheet], totalPages: 2, pagesUsed: min(totalSourcePages, 2))
    }


    public static func fourUpBooklet(_ totalSourcePages: Int, _ config: ImpositionConfig) -> ImpositionResult {
        let totalPages = padToMultiple(max(totalSourcePages, 8), 8)
        let numSheets = totalPages / 8
        let sw = config.sheetW
        let sh = config.sheetH

        var sheets: [SheetDefinition] = []

        for s in 0..<numSheets {
            let n = totalPages
            let base = s * 4

            let frontPages = [
                pageOrBlank(n - base, source: totalSourcePages),
                pageOrBlank(n - base - 1, source: totalSourcePages),
                pageOrBlank(base + 1, source: totalSourcePages),
                pageOrBlank(base + 2, source: totalSourcePages),
            ]
            let frontRotations = [180, 180, 0, 0]

            let backPages = [
                pageOrBlank(base + 3, source: totalSourcePages),
                pageOrBlank(base + 4, source: totalSourcePages),
                pageOrBlank(n - base - 2, source: totalSourcePages),
                pageOrBlank(n - base - 3, source: totalSourcePages),
            ]
            let backRotations = [0, 0, 180, 180]

            sheets.append(SheetDefinition(
                id: s + 1,
                front: buildGrid(pageNumbers: frontPages, rows: 2, cols: 2,
                                 sheetW: sw, sheetH: sh,
                                 marginMm: config.marginMm, gutterMm: config.gutterMm,
                                 side: .front, rotations: frontRotations),
                back: buildGrid(pageNumbers: backPages, rows: 2, cols: 2,
                                sheetW: sw, sheetH: sh,
                                marginMm: config.marginMm, gutterMm: config.gutterMm,
                                side: .back, rotations: backRotations)
            ))
        }

        return ImpositionResult(sheets: sheets, totalPages: totalPages, pagesUsed: totalSourcePages)
    }


    private static let gangRunGrids: [Int: (rows: Int, cols: Int)] = [
        2: (1, 2), 4: (2, 2), 6: (2, 3), 8: (2, 4), 9: (3, 3),
    ]

    public static func gangRun(_ totalSourcePages: Int, _ config: ImpositionConfig) -> ImpositionResult {
        let (rows, cols) = gangRunGrids[config.nUp] ?? (1, 2)
        let nUp = rows * cols
        let sw = config.sheetW
        let sh = config.sheetH

        let numSourcePages = max(totalSourcePages, 1)
        var sheets: [SheetDefinition] = []

        for s in 0..<numSourcePages {
            let srcPage = s + 1
            let frontPages = Array(repeating: srcPage, count: nUp)
            let backPages = Array(repeating: srcPage, count: nUp)

            sheets.append(SheetDefinition(
                id: s + 1,
                front: buildGrid(pageNumbers: frontPages, rows: rows, cols: cols,
                                 sheetW: sw, sheetH: sh,
                                 marginMm: config.marginMm, gutterMm: config.gutterMm,
                                 side: .front),
                back: buildGrid(pageNumbers: backPages, rows: rows, cols: cols,
                                sheetW: sw, sheetH: sh,
                                marginMm: config.marginMm, gutterMm: config.gutterMm,
                                side: .back)
            ))
        }

        return ImpositionResult(sheets: sheets, totalPages: numSourcePages, pagesUsed: numSourcePages)
    }


    public static func customNUp(_ totalSourcePages: Int, _ config: ImpositionConfig) -> ImpositionResult {
        let rows = config.customRows
        let cols = config.customCols
        let cellsPerSide = rows * cols
        let cellsPerSheet = cellsPerSide * 2

        let sw = config.sheetW
        let sh = config.sheetH

        let totalPadded = padToMultiple(max(totalSourcePages, cellsPerSheet), cellsPerSheet)
        let numSheets = totalPadded / cellsPerSheet

        var sheets: [SheetDefinition] = []

        for s in 0..<numSheets {
            let frontStart = s * cellsPerSheet + 1
            let backStart = frontStart + cellsPerSide

            let frontPages = (0..<cellsPerSide).map { i in
                pageOrBlank(frontStart + i, source: totalSourcePages)
            }
            let backPages = (0..<cellsPerSide).map { i in
                pageOrBlank(backStart + i, source: totalSourcePages)
            }

            sheets.append(SheetDefinition(
                id: s + 1,
                front: buildGrid(pageNumbers: frontPages, rows: rows, cols: cols,
                                 sheetW: sw, sheetH: sh,
                                 marginMm: config.marginMm, gutterMm: config.gutterMm,
                                 side: .front),
                back: buildGrid(pageNumbers: backPages, rows: rows, cols: cols,
                                sheetW: sw, sheetH: sh,
                                marginMm: config.marginMm, gutterMm: config.gutterMm,
                                side: .back)
            ))
        }

        return ImpositionResult(sheets: sheets, totalPages: totalPadded, pagesUsed: totalSourcePages)
    }


    public struct OuterEdges: Sendable {
        public let left: Bool
        public let right: Bool
        public let top: Bool
        public let bottom: Bool
    }

    public static func getOuterEdges(_ placements: [ImpositionPlacement]) -> [OuterEdges] {
        guard !placements.isEmpty else { return [] }
        let eps = 0.5
        let minX = placements.map(\.x).min()!
        let maxX = placements.map { $0.x + $0.width }.max()!
        let minY = placements.map(\.y).min()!
        let maxY = placements.map { $0.y + $0.height }.max()!

        return placements.map { p in
            OuterEdges(
                left: abs(p.x - minX) < eps,
                right: abs(p.x + p.width - maxX) < eps,
                top: abs(p.y - minY) < eps,
                bottom: abs(p.y + p.height - maxY) < eps
            )
        }
    }
}


public nonisolated enum ImposedPDFWriter {
    /// Front then back of every sheet, one PDF page each.
    public static func write(_ source: PDFDocument, result: ImpositionResult, config: ImpositionConfig, progress: ((Double) -> Void)? = nil) -> Data? {
        let width = config.sheetW * ImpositionEngine.mmToPoints
        let height = config.sheetH * ImpositionEngine.mmToPoints
        return SheetPDF.write(size: CGSize(width: width, height: height), pages: result.sheets.count * 2) { index, context in
            let sheet = result.sheets[index / 2]
            drawPlacements(context, index % 2 == 0 ? sheet.front : sheet.back, source, width, height, config)
            if index % 2 == 1 { progress?(Double(index / 2 + 1) / Double(max(1, result.sheets.count))) }
        }
    }

    private static func drawPlacements(_ ctx: CGContext, _ placements: [ImpositionPlacement], _ source: PDFDocument,
                                       _ sheetWPt: Double, _ sheetHPt: Double, _ config: ImpositionConfig) {
        let scale = ImpositionEngine.mmToPoints
        for p in placements {
            guard p.pageNumber > 0, p.pageNumber <= source.pageCount, let page = source.page(at: p.pageNumber - 1) else { continue }
            let (px, py, pw, ph) = (p.x * scale, p.y * scale, p.width * scale, p.height * scale)
            ctx.saveGState()
            ctx.clip(to: CGRect(x: px, y: py, width: pw, height: ph))
            ctx.translateBy(x: px + pw / 2, y: py + ph / 2)
            if p.rotation != 0 { ctx.rotate(by: Double(p.rotation) * .pi / 180.0) }
            let pageRect = page.bounds(for: .mediaBox)
            let fitScale: Double = switch config.scaling {
            case .fit: min(pw / pageRect.width, ph / pageRect.height)
            case .fill: max(pw / pageRect.width, ph / pageRect.height)
            case .actual: 1.0
            }
            // pdf origin bottom-left
            ctx.scaleBy(x: 1, y: -1)
            ctx.translateBy(x: -pageRect.width * fitScale / 2, y: -pageRect.height * fitScale / 2)
            ctx.scaleBy(x: fitScale, y: fitScale)
            if let cgPage = page.pageRef { ctx.drawPDFPage(cgPage) }
            ctx.restoreGState()
        }
        if config.cropMarks { drawCropMarks(ctx, placements, scale) }
        drawFoldLines(ctx, config.layoutId, sheetWPt, sheetHPt)
    }

    private static func drawCropMarks(_ ctx: CGContext, _ placements: [ImpositionPlacement], _ scale: Double) {
        ctx.saveGState()
        ctx.setStrokeColor(CGColor(gray: 0.33, alpha: 1))
        ctx.setLineWidth(0.5)
        let mark: CGFloat = 10
        let edges = ImpositionEngine.getOuterEdges(placements)
        func line(_ a: CGPoint, _ b: CGPoint) {
            ctx.move(to: a)
            ctx.addLine(to: b)
        }
        for (i, p) in placements.enumerated() {
            let e = edges[i]
            let (x, y, w, h) = (p.x * scale, p.y * scale, p.width * scale, p.height * scale)
            if e.left { line(CGPoint(x: x - mark, y: y), CGPoint(x: x, y: y)) }
            if e.top { line(CGPoint(x: x, y: y - mark), CGPoint(x: x, y: y)) }
            if e.right { line(CGPoint(x: x + w, y: y), CGPoint(x: x + w + mark, y: y)) }
            if e.top { line(CGPoint(x: x + w, y: y - mark), CGPoint(x: x + w, y: y)) }
            if e.left { line(CGPoint(x: x - mark, y: y + h), CGPoint(x: x, y: y + h)) }
            if e.bottom { line(CGPoint(x: x, y: y + h), CGPoint(x: x, y: y + h + mark)) }
            if e.right { line(CGPoint(x: x + w, y: y + h), CGPoint(x: x + w + mark, y: y + h)) }
            if e.bottom { line(CGPoint(x: x + w, y: y + h), CGPoint(x: x + w, y: y + h + mark)) }
        }
        ctx.strokePath()
        ctx.restoreGState()
    }

    private static func drawFoldLines(_ ctx: CGContext, _ layout: ImpositionLayoutID, _ w: Double, _ h: Double) {
        ctx.saveGState()
        // system blue at 40%
        ctx.setStrokeColor(CGColor(srgbRed: 0, green: 0.478, blue: 1, alpha: 0.4))
        ctx.setLineWidth(0.5)
        ctx.setLineDash(phase: 0, lengths: [4, 3])
        switch layout {
        case .saddleStitch, .perfectBind, .stepAndRepeat:
            ctx.move(to: CGPoint(x: w / 2, y: 0))
            ctx.addLine(to: CGPoint(x: w / 2, y: h))
        case .fourUpBooklet:
            ctx.move(to: CGPoint(x: w / 2, y: 0))
            ctx.addLine(to: CGPoint(x: w / 2, y: h))
            ctx.move(to: CGPoint(x: 0, y: h / 2))
            ctx.addLine(to: CGPoint(x: w, y: h / 2))
        default:
            break
        }
        ctx.strokePath()
        ctx.restoreGState()
    }
}

/// A PDF of equal pages drawn top-left origin, as UIKit's PDF renderer draws.
public nonisolated enum SheetPDF {
    public static func write(size: CGSize, pages: Int, draw: (Int, CGContext) -> Void) -> Data? {
        let data = NSMutableData()
        var box = CGRect(origin: .zero, size: size)
        guard pages > 0, let consumer = CGDataConsumer(data: data), let context = CGContext(consumer: consumer, mediaBox: &box, nil) else { return nil }
        for index in 0..<pages {
            context.beginPDFPage(nil)
            context.translateBy(x: 0, y: size.height)
            context.scaleBy(x: 1, y: -1)
            draw(index, context)
            context.endPDFPage()
        }
        context.closePDF()
        return data as Data
    }
}

#if DEBUG
extension ImpositionEngine {
    public static func selfCheck() {
        let config = ImpositionConfig()
        let saddle = ImpositionLayoutID.saddleStitch.calculate(totalSourcePages: 6, config: config)
        assert(saddle.totalPages == 8 && saddle.totalSheets == 2 && saddle.blanksAdded == 2)
        assert(saddle.sheets[0].front.map(\.pageNumber) == [0, 1] && saddle.sheets[0].back.map(\.pageNumber) == [2, 0])
        let bound = ImpositionLayoutID.perfectBind.calculate(totalSourcePages: 20, config: ImpositionConfig(signaturePages: 8))
        assert(bound.totalPages == 24 && bound.sheets.last?.signature == 2)
        let booklet = ImpositionLayoutID.fourUpBooklet.calculate(totalSourcePages: 8, config: config)
        assert(booklet.totalSheets == 1 && booklet.sheets[0].front.map(\.pageNumber) == [8, 7, 1, 2])
        let gang = ImpositionLayoutID.gangRun.calculate(totalSourcePages: 2, config: ImpositionConfig(nUp: 6))
        assert(gang.totalSheets == 2 && gang.sheets[0].front.count == 6)
        let custom = ImpositionLayoutID.customNUp.calculate(totalSourcePages: 9, config: ImpositionConfig(customRows: 2, customCols: 3))
        assert(custom.totalSheets == 1 && custom.totalPages == 12)
        // long edge on landscape tumbles
        assert(saddle.sheets[0].back[0].rotation == 180)
        let flat = ImpositionLayoutID.saddleStitch.calculate(totalSourcePages: 4, config: ImpositionConfig(duplexFlip: .shortEdge))
        assert(flat.sheets[0].back[0].rotation == 0)
        let edges = getOuterEdges(booklet.sheets[0].front)
        assert(edges[0].left && edges[0].top && !edges[0].right && edges[3].right && edges[3].bottom)
    }
}
#endif
