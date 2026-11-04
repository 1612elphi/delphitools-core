import CoreGraphics
import Foundation

/// One page placed in a grid cell on one side of the sheet; row 0 is the top.
public nonisolated struct ZinePlacement: Sendable {
    /// 1-based slot
    public let pageNumber: Int
    public let col: Int
    public let row: Int
    /// 0 or 180
    public let rotation: Double
}

public nonisolated struct ZineFoldLine: Sendable {
    public enum Axis: Sendable { case vertical, horizontal }
    public enum Kind: Sendable { case mountain, valley }
    public let axis: Axis
    /// fraction across the sheet: x for vertical, y from the top for horizontal
    public let pos: Double
    public let kind: Kind
}

/// Fractions of the sheet, top-left origin.
public nonisolated struct ZineCutLine: Sendable {
    public let x1, y1, x2, y2: Double
}

public nonisolated struct ZineSide: Sendable {
    public enum Side: Sendable { case front, back }
    public let side: Side
    public let placements: [ZinePlacement]
}

/// The folding steps for a layout; the app words each one.
public nonisolated enum ZineStep: Equatable, Sendable {
    case printSingle, printDuplexShortEdge
    case foldLengthwise, foldWidthwise, foldWidthwiseAgain, unfoldEight, cutSlit, pushTogether
    case cutStrips
    case foldConcertina(panels: Int, split: Bool)
    case crease
    case readFrontBack(panels: Int, split: Bool)
    case readPanels(split: Bool)
}

public nonisolated struct ZineFoldLayout: Sendable {
    public let cols: Int
    public let rows: Int
    /// slots to fill across all sides
    public let pageCount: Int
    /// one for single-sided, two for double-sided
    public let sides: [ZineSide]
    public let foldLines: [ZineFoldLine]
    public let cutLines: [ZineCutLine]
    public let steps: [ZineStep]
}

public nonisolated enum ZineFold: String, CaseIterable, Identifiable, Sendable {
    case miniEight, accordion

    public var id: String { rawValue }
    public var configurablePanels: Bool { self == .accordion }
    public var supportsDoubleSided: Bool { self == .accordion }
    public var supportsSplit: Bool { self == .accordion }

    public static let accordionPanels = [4, 6, 8]

    public func layout(panels: Int, doubleSided: Bool, split: Bool) -> ZineFoldLayout {
        switch self {
        case .miniEight: Self.miniEight()
        case .accordion: Self.accordion(panels: panels, doubleSided: doubleSided, split: split)
        }
    }

    /// One landscape sheet, 4 × 2: top row 5 4 3 2 turned, bottom row 6 7 8 1; folded and slit it reads 1 to 8.
    static func miniEight() -> ZineFoldLayout {
        let placements = [5, 4, 3, 2].enumerated().map { ZinePlacement(pageNumber: $1, col: $0, row: 0, rotation: 180) }
            + [6, 7, 8, 1].enumerated().map { ZinePlacement(pageNumber: $1, col: $0, row: 1, rotation: 0) }
        return ZineFoldLayout(
            cols: 4, rows: 2, pageCount: 8,
            sides: [ZineSide(side: .front, placements: placements)],
            foldLines: [
                ZineFoldLine(axis: .vertical, pos: 0.25, kind: .valley),
                ZineFoldLine(axis: .vertical, pos: 0.5, kind: .mountain),
                ZineFoldLine(axis: .vertical, pos: 0.75, kind: .valley),
                ZineFoldLine(axis: .horizontal, pos: 0.5, kind: .mountain),
            ],
            // middle two columns only
            cutLines: [ZineCutLine(x1: 0.25, y1: 0.5, x2: 0.75, y2: 0.5)],
            steps: [.printSingle, .foldLengthwise, .foldWidthwise, .foldWidthwiseAgain, .unfoldEight, .cutSlit, .pushTogether]
        )
    }

    /// N vertical panels, 1 × N. Double-sided puts N+1…2N on the back for a short-edge flip; split stacks two
    /// identical lanes with one cut between them, so the slot count stays the same.
    static func accordion(panels: Int, doubleSided: Bool, split: Bool) -> ZineFoldLayout {
        let n = max(2, panels)
        let rows = split ? 2 : 1
        func side(_ side: ZineSide.Side) -> ZineSide {
            ZineSide(side: side, placements: (0..<rows).flatMap { r in
                (0..<n).map { c in ZinePlacement(pageNumber: side == .front ? c + 1 : n + 1 + c, col: c, row: r, rotation: 0) }
            })
        }
        let folds = (1..<n).map { ZineFoldLine(axis: .vertical, pos: Double($0) / Double(n), kind: $0 % 2 == 1 ? .valley : .mountain) }
        let steps: [ZineStep] = [doubleSided ? .printDuplexShortEdge : .printSingle] + (split ? [.cutStrips] : [])
            + [.foldConcertina(panels: n, split: split), .crease, doubleSided ? .readFrontBack(panels: n, split: split) : .readPanels(split: split)]
        return ZineFoldLayout(
            cols: n, rows: rows, pageCount: doubleSided ? n * 2 : n,
            sides: doubleSided ? [side(.front), side(.back)] : [side(.front)],
            foldLines: folds,
            cutLines: split ? [ZineCutLine(x1: 0, y1: 0.5, x2: 1, y2: 0.5)] : [],
            steps: steps
        )
    }

    /// Landscape sheet of `paperMm` either way round, one PDF page per printed side.
    public static func pdf(layout: ZineFoldLayout, images: [(image: CGImage, fills: Bool)?], paperMm: CGSize) -> Data? {
        let width = max(paperMm.width, paperMm.height) / 25.4 * 72
        let height = min(paperMm.width, paperMm.height) / 25.4 * 72
        let cellW = width / CGFloat(layout.cols), cellH = height / CGFloat(layout.rows)
        return SheetPDF.write(size: CGSize(width: width, height: height), pages: layout.sides.count) { index, ctx in
            let side = layout.sides[index]
            for placement in side.placements {
                let slot = placement.pageNumber - 1
                guard images.indices.contains(slot), let page = images[slot] else { continue }
                let cell = CGRect(x: CGFloat(placement.col) * cellW, y: CGFloat(placement.row) * cellH, width: cellW, height: cellH)
                let size = CGSize(width: page.image.width, height: page.image.height)
                let scale = page.fills ? max(cellW / size.width, cellH / size.height) : min(cellW / size.width, cellH / size.height)
                ctx.saveGState()
                ctx.clip(to: cell)
                ctx.translateBy(x: cell.midX, y: cell.midY)
                if placement.rotation != 0 { ctx.rotate(by: placement.rotation * .pi / 180) }
                // images draw bottom-left up
                ctx.scaleBy(x: 1, y: -1)
                ctx.draw(page.image, in: CGRect(x: -size.width * scale / 2, y: -size.height * scale / 2, width: size.width * scale, height: size.height * scale))
                ctx.restoreGState()
            }
            ctx.saveGState()
            ctx.setStrokeColor(CGColor(gray: 0.5, alpha: 0.5))
            ctx.setLineWidth(0.5)
            ctx.setLineDash(phase: 0, lengths: [4, 4])
            for fold in layout.foldLines {
                let along = fold.axis == .vertical
                let at = CGFloat(fold.pos) * (along ? width : height)
                ctx.move(to: along ? CGPoint(x: at, y: 0) : CGPoint(x: 0, y: at))
                ctx.addLine(to: along ? CGPoint(x: at, y: height) : CGPoint(x: width, y: at))
            }
            ctx.strokePath()
            ctx.restoreGState()
            // cuts on the front only
            guard side.side == .front, !layout.cutLines.isEmpty else { return }
            ctx.saveGState()
            ctx.setStrokeColor(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 0.7))
            ctx.setLineWidth(1)
            for cut in layout.cutLines {
                ctx.move(to: CGPoint(x: cut.x1 * width, y: cut.y1 * height))
                ctx.addLine(to: CGPoint(x: cut.x2 * width, y: cut.y2 * height))
            }
            ctx.strokePath()
            ctx.restoreGState()
        }
    }

    #if DEBUG
    public static func selfCheck() {
        let mini = ZineFold.miniEight.layout(panels: 8, doubleSided: true, split: true)
        assert(mini.pageCount == 8 && mini.sides.count == 1 && Set(mini.sides[0].placements.map(\.pageNumber)) == Set(1...8))
        assert(mini.sides[0].placements.filter { $0.row == 0 }.allSatisfy { $0.rotation == 180 })
        let accordion = ZineFold.accordion.layout(panels: 6, doubleSided: true, split: true)
        assert(accordion.pageCount == 12 && accordion.rows == 2 && accordion.sides[1].placements.first?.pageNumber == 7)
        assert(accordion.foldLines.count == 5 && accordion.cutLines.count == 1 && accordion.steps.contains(.cutStrips))
        assert(ZineFold.accordion.layout(panels: 4, doubleSided: false, split: false).steps.first == .printSingle)
    }
    #endif
}
