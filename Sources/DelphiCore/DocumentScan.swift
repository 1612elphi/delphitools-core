import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers
import Vision

public enum DocumentScanText {
    /// One recognised line.
    public struct Line: Sendable, Equatable {
        public let text: String
        // page share, top-left origin
        public let box: CGRect
        // 0...1
        public let confidence: Float
    }

    public static let thumbnailPixels = 480
    // a4 long side, points
    public static let longSide: CGFloat = 842

    /// Page size in points for a scan of `pixels`: the long side A4's 842 pt, the short side in proportion.
    public static func pageSize(pixels: CGSize) -> CGSize {
        let long = max(pixels.width, pixels.height, 1)
        return CGSize(width: (pixels.width / long * longSide).rounded(), height: (pixels.height / long * longSide).rounded())
    }

    /// Vision's accurate text recognition of `image`, in reading order.
    public static func recognise(_ image: CGImage) -> [Line] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = true
        do {
            try VNImageRequestHandler(cgImage: image).perform([request])
        } catch {
            return []
        }
        return readingOrder((request.results ?? []).compactMap { observation in
            guard let best = observation.topCandidates(1).first else { return nil }
            let box = observation.boundingBox
            return Line(text: best.string, box: CGRect(x: box.minX, y: 1 - box.maxY, width: box.width, height: box.height), confidence: best.confidence)
        })
    }

    /// `lines` row by row from the top, each row from the left; Vision returns a table column by column.
    public static func readingOrder(_ lines: [Line]) -> [Line] {
        rows(lines).flatMap { $0 }
    }

    /// `lines` in rows: a line joins the row above when their centres are less than half the shorter line's height apart.
    public static func rows(_ lines: [Line]) -> [[Line]] {
        var rows: [[Line]] = []
        for line in lines.sorted(by: { $0.box.midY < $1.box.midY }) {
            if let last = rows.last?.last, abs(line.box.midY - last.box.midY) < min(line.box.height, last.box.height) / 2 {
                rows[rows.count - 1].append(line)
            } else {
                rows.append([line])
            }
        }
        return rows.map { $0.sorted { $0.box.minX < $1.box.minX } }
    }

    /// One line of text per row, the lines of a row apart by tabs, as a spreadsheet pastes them.
    public static func text(_ lines: [Line]) -> String {
        rows(lines).map { $0.map(\.text).joined(separator: "\t") }.joined(separator: "\n")
    }
}

/// The pages as JPEG pictures with the recognised lines as invisible text over them, so the PDF can be searched and selected.
public enum DocumentScanPDF {
    /// Writes `pages` to a PDF at `url`, a page per image sized by `DocumentScanText.pageSize(pixels:)`; `progress` gets the share done after each page. Throws on cancellation.
    public static func write(_ pages: [(image: CGImage, lines: [DocumentScanText.Line])], to url: URL, progress: (Double) -> Void) throws {
        guard let context = CGContext(url as CFURL, mediaBox: nil, nil) else { throw CocoaError(.fileWriteUnknown) }
        for (index, page) in pages.enumerated() {
            try Task.checkCancellation()
            var box = CGRect(origin: .zero, size: DocumentScanText.pageSize(pixels: CGSize(width: page.image.width, height: page.image.height)))
            context.beginPage(mediaBox: &box)
            autoreleasepool { context.draw(jpeg(page.image) ?? page.image, in: box) }
            drawText(page.lines, on: box, in: context)
            context.endPage()
            progress(Double(index + 1) / Double(pages.count))
        }
        context.closePDF()
    }

    // pdf keeps jpeg data
    private static func jpeg(_ image: CGImage) -> CGImage? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
        guard CGImageDestinationFinalize(destination), let provider = CGDataProvider(data: data) else { return nil }
        return CGImage(jpegDataProviderSource: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }

    private static func drawText(_ lines: [DocumentScanText.Line], on page: CGRect, in context: CGContext) {
        let unit = CTFontCreateWithName("Helvetica" as CFString, 1, nil)
        let unitHeight = CTFontGetAscent(unit) + CTFontGetDescent(unit)
        context.saveGState()
        context.setTextDrawingMode(.invisible)
        for line in lines where !line.text.isEmpty {
            // pdf origin: bottom left
            let rect = CGRect(
                x: line.box.minX * page.width, y: (1 - line.box.maxY) * page.height,
                width: line.box.width * page.width, height: line.box.height * page.height
            )
            let font = CTFontCreateWithName("Helvetica" as CFString, max(1, rect.height / unitHeight), nil)
            let set = CTLineCreateWithAttributedString(NSAttributedString(string: line.text, attributes: [.font: font]))
            let width = CTLineGetTypographicBounds(set, nil, nil, nil)
            guard width > 0 else { continue }
            context.textMatrix = CGAffineTransform(scaleX: rect.width / width, y: 1)
            context.textPosition = CGPoint(x: rect.minX, y: rect.minY + CTFontGetDescent(font))
            CTLineDraw(set, context)
        }
        context.restoreGState()
    }
}
