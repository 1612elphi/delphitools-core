import CoreGraphics
import CoreText
import Foundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers

public nonisolated struct PDFSource: Sendable {
    public let url: URL
    public let name: String
    public let pageCount: Int
    public let byteCount: Int

    public init(url: URL, name: String, pageCount: Int, byteCount: Int) {
        (self.url, self.name, self.pageCount, self.byteCount) = (url, name, pageCount, byteCount)
    }

    public var stem: String { (name as NSString).deletingPathExtension }
}

public nonisolated enum PDFDocumentLoader {
    public static func open(_ url: URL) -> PDFDocument? {
        guard let document = PDFDocument(url: url), !document.isLocked, document.pageCount > 0 else { return nil }
        return document
    }

    public static func source(_ url: URL) -> PDFSource? {
        guard let document = open(url) else { return nil }
        let bytes = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        return PDFSource(url: url, name: url.lastPathComponent, pageCount: document.pageCount, byteCount: bytes)
    }

    /// The facts and every page's size as viewed.
    public static func pages(_ url: URL) -> (PDFSource, [CGSize])? {
        guard let source = source(url), let document = open(url) else { return nil }
        return (source, (0..<document.pageCount).compactMap { document.page(at: $0).map(displaySize) })
    }

    public static func displaySize(_ page: PDFPage) -> CGSize {
        PDFCropEngine.displaySize(box: page.bounds(for: .cropBox), rotation: page.rotation)
    }

    /// One page as viewed with `rotation` added, its long edge `maxEdge` pixels.
    public static func thumbnail(_ url: URL, page index: Int, rotation: Int = 0, maxEdge: CGFloat) -> CGImage? {
        guard let document = open(url) else { return nil }
        return thumbnail(document, page: index, rotation: rotation, maxEdge: maxEdge)
    }

    public static func thumbnail(_ document: PDFDocument, page index: Int, rotation: Int = 0, maxEdge: CGFloat) -> CGImage? {
        guard let page = document.page(at: index) else { return nil }
        if rotation != 0 { page.rotation = PDFPagesEngine.normaliseRotation(page.rotation + rotation) }
        let size = displaySize(page)
        // released document draws nothing
        return withExtendedLifetime(document) {
            bitmap(size: size, scale: maxEdge / max(size.width, size.height, 1)) { drawPage(page, in: $0) }
        }
    }

    // ponytail: 1x, 240 px long edge, about 160 MB for 500 pages; render only visible cells if that bites
    /// Every page's thumbnail, four per batch, off the main thread.
    public static func thumbnailBatches(_ url: URL, maxEdge: CGFloat = 240) -> AsyncStream<[(Int, CGImage)]> {
        AsyncStream { continuation in
            let task = Task.detached(priority: .utility) {
                guard let document = open(url) else { return continuation.finish() }
                var batch: [(Int, CGImage)] = []
                for index in 0..<document.pageCount where !Task.isCancelled {
                    if let picture = thumbnail(document, page: index, maxEdge: maxEdge) { batch.append((index, picture)) }
                    if batch.count == 4 || index == document.pageCount - 1 {
                        continuation.yield(batch)
                        batch = []
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// A new PDF with every page redrawn by `draw`; any failure fails all.
    public static func redraw(_ document: PDFDocument, draw: (PDFPage, Int, CGContext, CGSize) -> Bool) -> Data? {
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data), let context = CGContext(consumer: consumer, mediaBox: nil, nil) else { return nil }
        var complete = true
        for index in 0..<document.pageCount where complete {
            autoreleasepool {
                guard let page = document.page(at: index) else {
                    complete = false
                    return
                }
                let size = displaySize(page)
                var box = CGRect(origin: .zero, size: size)
                context.beginPage(mediaBox: &box)
                complete = draw(page, index, context, size)
                context.endPage()
            }
        }
        context.closePDF()
        return complete ? data as Data : nil
    }

    public static func drawPage(_ page: PDFPage, in context: CGContext) {
        context.saveGState()
        page.draw(with: .cropBox, to: context)
        context.restoreGState()
    }

    // ponytail: 40 MP cap, 160 MB of RGBA; tile the render if poster pages need full dpi
    public static let maxBitmapPixels = 40_000_000.0

    /// Opaque white bitmap of `size` points at `scale` pixels per point; `draw` gets PDF space, bottom-left origin.
    public static func bitmap(size: CGSize, scale: Double, draw: (CGContext) -> Void) -> CGImage? {
        let scale = PDFPagesEngine.cappedScale(scale, size: size, maxPixels: maxBitmapPixels)
        let width = max(1, Int((size.width * scale).rounded())), height = max(1, Int((size.height * scale).rounded()))
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { return nil }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.scaleBy(x: CGFloat(width) / max(size.width, 1), y: CGFloat(height) / max(size.height, 1))
        draw(context)
        return context.makeImage()
    }

    public static func encode(_ image: CGImage, as type: UTType, quality: Double? = nil) -> Data? {
        let out = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(out, type.identifier as CFString, 1, nil) else { return nil }
        let options = quality.map { [kCGImageDestinationLossyCompressionQuality: $0] as CFDictionary }
        CGImageDestinationAddImage(destination, image, options)
        return CGImageDestinationFinalize(destination) ? out as Data : nil
    }

    /// Embeds as JPEG bytes, not re-inflated pixels.
    static func jpegImage(_ image: CGImage, quality: Double) -> CGImage? {
        guard let jpeg = encode(image, as: .jpeg, quality: quality), let provider = CGDataProvider(data: jpeg as CFData) else { return nil }
        return CGImage(jpegDataProviderSource: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }

    public static func byteLabel(_ count: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(count), countStyle: .file)
    }

    /// `scale` 1 is 72 DPI; named `<stem>-page-<n>.png`.
    public static func pngs(_ url: URL, pages: [Int], scale: Double, stem: String) -> [(String, Data)]? {
        guard let document = open(url) else { return nil }
        var files: [(String, Data)] = []
        for index in pages {
            let file: (String, Data)? = autoreleasepool {
                guard let page = document.page(at: index),
                      let image = bitmap(size: displaySize(page), scale: scale, draw: { drawPage(page, in: $0) }),
                      let png = encode(image, as: .png) else { return nil }
                return ("\(stem)-page-\(index + 1).png", png)
            }
            guard let file else { return nil }
            files.append(file)
        }
        return files
    }
}

public nonisolated enum PDFOrganiserEngine {
    public struct PageRef: Sendable {
        public let url: URL
        public let page: Int
        public var rotation: Int

        public init(url: URL, page: Int, rotation: Int = 0) {
            (self.url, self.page, self.rotation) = (url, page, rotation)
        }
    }

    public static func build(_ refs: [PageRef]) -> Data? {
        var documents: [URL: PDFDocument] = [:]
        return build(refs, documents: &documents)
    }

    /// `documents` caches opened sources across calls.
    public static func build(_ refs: [PageRef], documents: inout [URL: PDFDocument]) -> Data? {
        let out = PDFDocument()
        for ref in refs {
            if documents[ref.url] == nil { documents[ref.url] = PDFDocumentLoader.open(ref.url) }
            guard let page = documents[ref.url]?.page(at: ref.page)?.copy() as? PDFPage else { return nil }
            page.rotation = PDFPagesEngine.normaliseRotation(page.rotation + ref.rotation)
            out.insert(page, at: out.pageCount)
        }
        guard out.pageCount > 0 else { return nil }
        // copies draw from sources
        return withExtendedLifetime(documents) { out.dataRepresentation() }
    }

    /// One PDF per group, named by `names`; nil if any fails.
    public static func split(_ parts: [(name: String, refs: [PageRef])]) -> [(String, Data)]? {
        var documents: [URL: PDFDocument] = [:]
        var files: [(String, Data)] = []
        for part in parts {
            guard let data = autoreleasepool(invoking: { build(part.refs, documents: &documents) }) else { return nil }
            files.append((part.name, data))
        }
        return files
    }
}

public nonisolated enum PDFCompressEngine {
    public enum Mode: Sendable, Equatable {
        /// Rewrites the file; images untouched.
        case keep
        /// Images re-encoded as JPEG, optionally downsampled to screen resolution; text and vectors kept.
        case recompress(downsample: Bool)
        /// Every page becomes one JPEG; text stops being text.
        case rasterise(dpi: Double, quality: Double)
    }

    public static func compress(_ url: URL, mode: Mode) -> Data? {
        guard let document = PDFDocumentLoader.open(url) else { return nil }
        // copies draw from source
        return withExtendedLifetime(document) { compress(document, mode: mode) }
    }

    private static func compress(_ document: PDFDocument, mode: Mode) -> Data? {
        switch mode {
        case .keep:
            return rebuilt(document).dataRepresentation()
        case .recompress(let downsample):
            // options ignored unless rebuilt
            return rebuilt(document).dataRepresentation(options: [
                PDFDocumentWriteOption.saveImagesAsJPEGOption: true,
                PDFDocumentWriteOption.optimizeImagesForScreenOption: downsample,
            ])
        case .rasterise(let dpi, let quality):
            return PDFDocumentLoader.redraw(document) { page, _, context, size in
                guard let bitmap = PDFDocumentLoader.bitmap(size: size, scale: dpi / 72, draw: { PDFDocumentLoader.drawPage(page, in: $0) }),
                      let image = PDFDocumentLoader.jpegImage(bitmap, quality: quality) else { return false }
                context.draw(image, in: CGRect(origin: .zero, size: size))
                return true
            }
        }
    }

    private static func rebuilt(_ document: PDFDocument) -> PDFDocument {
        let out = PDFDocument()
        for index in 0..<document.pageCount {
            if let page = document.page(at: index)?.copy() as? PDFPage { out.insert(page, at: out.pageCount) }
        }
        out.documentAttributes = document.documentAttributes
        return out
    }
}

public nonisolated enum PDFStampRenderer {
    /// Vector rebuild: page content stays vector, annotations are flattened into it, links and the outline are dropped.
    public static func stamp(_ url: URL, options: PDFStampEngine.Options) -> Data? {
        guard let document = PDFDocumentLoader.open(url) else { return nil }
        let labels = PDFStampEngine.resolvePageNumbers(options.sections, pageCount: document.pageCount)
        return PDFDocumentLoader.redraw(document) { page, index, context, size in
            PDFDocumentLoader.drawPage(page, in: context)
            drawStamps(label: labels[index], total: document.pageCount, size: size, options: options, in: context)
            return true
        }
    }

    public static func preview(_ url: URL, page index: Int, options: PDFStampEngine.Options, maxEdge: CGFloat) -> CGImage? {
        guard let document = PDFDocumentLoader.open(url), let page = document.page(at: index) else { return nil }
        let labels = PDFStampEngine.resolvePageNumbers(options.sections, pageCount: document.pageCount)
        let size = PDFDocumentLoader.displaySize(page)
        return PDFDocumentLoader.bitmap(size: size, scale: maxEdge / max(size.width, size.height, 1)) { context in
            PDFDocumentLoader.drawPage(page, in: context)
            drawStamps(label: labels[index], total: document.pageCount, size: size, options: options, in: context)
        }
    }

    private static func drawStamps(label: String?, total: Int, size: CGSize, options: PDFStampEngine.Options, in context: CGContext) {
        let fontSize = max(4, options.fontSize)
        if options.numbersOn, let label {
            let text = PDFStampEngine.expandNumber(options.template, n: label, total: String(total))
            let line = line(text, font: options.font, size: fontSize, grey: 0, alpha: 1)
            let origin = PDFStampEngine.placeText(page: size, textWidth: width(line), fontSize: fontSize, anchor: options.numberAnchor, margin: options.margin)
            draw(line, at: origin, in: context)
        }
        let stamp = options.stampText
        guard options.stampOn, !stamp.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        if options.stampMode == .watermark {
            let wmSize = PDFStampEngine.watermarkSize(page: size, textLength: stamp.count)
            let line = line(stamp, font: options.font, size: wmSize, grey: 0, alpha: options.watermarkOpacity)
            let w = width(line)
            let half = wmSize * 0.35 / 2
            let k = cos(Double.pi / 4)
            context.saveGState()
            context.translateBy(x: size.width / 2 - (w / 2) * k + half * k, y: size.height / 2 - (w / 2) * k - half * k)
            context.rotate(by: .pi / 4)
            draw(line, at: .zero, in: context)
            context.restoreGState()
        } else {
            let line = line(stamp, font: options.font, size: fontSize, grey: 0.4, alpha: 1)
            let origin = PDFStampEngine.placeText(page: size, textWidth: width(line), fontSize: fontSize, anchor: options.stampAnchor, margin: options.margin)
            draw(line, at: origin, in: context)
        }
    }

    private static func line(_ text: String, font: PDFStampEngine.FontFamily, size: Double, grey: Double, alpha: Double) -> CTLine {
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName(font.postScriptName as CFString, size, nil),
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: grey, alpha: alpha),
        ]
        return CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
    }

    private static func width(_ line: CTLine) -> Double {
        CTLineGetTypographicBounds(line, nil, nil, nil)
    }

    private static func draw(_ line: CTLine, at origin: CGPoint, in context: CGContext) {
        context.textMatrix = .identity
        context.textPosition = origin
        CTLineDraw(line, context)
    }
}

public nonisolated enum PDFRotateCropWriter {
    public struct Geometry: Sendable {
        public let box: CGRect
        public let rotation: Int
    }

    public struct Edit: Sendable {
        /// 90° steps on top of the page's own
        public var rotation: Int
        /// page space; nil keeps the whole page
        public var crop: CGRect?

        public init(rotation: Int = 0, crop: CGRect? = nil) {
            (self.rotation, self.crop) = (rotation, crop)
        }
    }

    public static func geometry(_ url: URL) -> [Geometry]? {
        guard let document = PDFDocumentLoader.open(url) else { return nil }
        return (0..<document.pageCount).compactMap { index in
            document.page(at: index).map { Geometry(box: $0.bounds(for: .cropBox), rotation: $0.rotation) }
        }
    }

    public static func apply(_ url: URL, edits: [Edit]) -> Data? {
        guard let document = PDFDocumentLoader.open(url) else { return nil }
        for (index, edit) in edits.enumerated() {
            guard let page = document.page(at: index) else { continue }
            if edit.rotation != 0 { page.rotation = PDFPagesEngine.normaliseRotation(page.rotation + edit.rotation) }
            if let crop = edit.crop, let box = PDFCropEngine.intersectBox(crop, page.bounds(for: .cropBox)) {
                page.setBounds(box, for: .cropBox)
            }
        }
        return document.dataRepresentation()
    }
}

public nonisolated enum ImageToPDFEngine {
    /// An image file read for the page strip: its pixels as viewed and a thumbnail.
    public struct Item: Sendable {
        public let id = UUID()
        public let url: URL
        public let name: String
        public let pixels: CGSize
        public let thumbnail: CGImage

        public static func load(_ url: URL) -> Item? {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                  let width = properties[kCGImagePropertyPixelWidth] as? Int,
                  let height = properties[kCGImagePropertyPixelHeight] as? Int,
                  let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                      kCGImageSourceCreateThumbnailFromImageAlways: true,
                      kCGImageSourceCreateThumbnailWithTransform: true,
                      kCGImageSourceThumbnailMaxPixelSize: 480,
                  ] as CFDictionary)
            else { return nil }
            // exif 5-8: quarter turn
            let turned = (5...8).contains(properties[kCGImagePropertyOrientation] as? Int ?? 1)
            return Item(url: url, name: url.lastPathComponent,
                        pixels: turned ? CGSize(width: height, height: width) : CGSize(width: width, height: height), thumbnail: thumbnail)
        }
    }

    /// One page per image, decoded one at a time; nil if any page fails.
    public static func build(urls: [URL], options: ImageToPDFLayout.Options) -> Data? {
        let data = NSMutableData()
        guard !urls.isEmpty, let consumer = CGDataConsumer(data: data), let context = CGContext(consumer: consumer, mediaBox: nil, nil) else { return nil }
        var placed = 0
        for url in urls where !Task.isCancelled {
            autoreleasepool {
                guard let bitmap = embeddable(url),
                      let layout = ImageToPDFLayout.layout(imageSize: CGSize(width: bitmap.width, height: bitmap.height), options: options) else { return }
                var box = CGRect(origin: .zero, size: layout.page)
                context.beginPage(mediaBox: &box)
                context.saveGState()
                context.clip(to: layout.area)
                context.draw(bitmap, in: layout.placement)
                context.restoreGState()
                context.endPage()
                placed += 1
            }
        }
        context.closePDF()
        return placed == urls.count ? data as Data : nil
    }

    /// Upright; opaque images as JPEG to avoid flate bloat.
    private static func embeddable(_ url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              let upright = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceCreateThumbnailWithTransform: true,
                  kCGImageSourceThumbnailMaxPixelSize: max(width, height),
              ] as CFDictionary)
        else { return nil }
        let opaque = [.none, .noneSkipFirst, .noneSkipLast].contains(upright.alphaInfo)
        return opaque ? PDFDocumentLoader.jpegImage(upright, quality: 0.9) ?? upright : upright
    }
}
