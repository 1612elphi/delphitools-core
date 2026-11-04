import CoreGraphics
import Foundation
import PDFKit
import Testing
@testable import DelphiCore

@Test func pdfEngines() {
    PDFPagesEngine.selfCheck()
    PDFCropEngine.selfCheck()
    PDFStampEngine.selfCheck()
    ImageToPDFLayout.selfCheck()
    ImpositionEngine.selfCheck()
    ZineFold.selfCheck()
}

private func samplePDF(pages: Int) throws -> URL {
    let data = try #require(SheetPDF.write(size: CGSize(width: 200, height: 300), pages: pages) { index, context in
        context.setFillColor(CGColor(gray: Double(index) / Double(pages), alpha: 1))
        context.fill(CGRect(x: 20, y: 20, width: 100, height: 100))
    })
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("pdf-tests-\(UUID().uuidString).pdf")
    try data.write(to: url)
    return url
}

@Test func pdfRender() throws {
    let url = try samplePDF(pages: 3)
    defer { try? FileManager.default.removeItem(at: url) }
    let (source, sizes) = try #require(PDFDocumentLoader.pages(url))
    #expect(source.pageCount == 3 && sizes == Array(repeating: CGSize(width: 200, height: 300), count: 3))
    let thumbnail = try #require(PDFDocumentLoader.thumbnail(url, page: 0, rotation: 90, maxEdge: 60))
    #expect(thumbnail.width == 60 && thumbnail.height == 40)

    let merged = try #require(PDFOrganiserEngine.build([.init(url: url, page: 2, rotation: 90), .init(url: url, page: 0)]))
    let document = try #require(PDFDocument(data: merged))
    #expect(document.pageCount == 2 && document.page(at: 0)?.rotation == 90)
    #expect(PDFOrganiserEngine.split([("a.pdf", [.init(url: url, page: 1)]), ("b.pdf", [.init(url: url, page: 9)])]) == nil)

    for mode in [PDFCompressEngine.Mode.keep, .recompress(downsample: true), .rasterise(dpi: 72, quality: 0.5)] {
        #expect(PDFCompressEngine.compress(url, mode: mode).flatMap(PDFDocument.init(data:))?.pageCount == 3)
    }
    var options = PDFStampEngine.Options()
    (options.stampOn, options.stampText, options.stampMode) = (true, "DRAFT", .watermark)
    #expect(PDFStampRenderer.stamp(url, options: options).flatMap(PDFDocument.init(data:))?.pageCount == 3)
    #expect(PDFStampRenderer.preview(url, page: 1, options: options, maxEdge: 100) != nil)

    let cropped = try #require(PDFRotateCropWriter.apply(url, edits: [.init(rotation: 90, crop: CGRect(x: 10, y: 10, width: 50, height: 50))]))
    let page = try #require(PDFDocument(data: cropped)?.page(at: 0))
    #expect(page.rotation == 90 && page.bounds(for: .cropBox) == CGRect(x: 10, y: 10, width: 50, height: 50))
    #expect(PDFDocumentLoader.pngs(url, pages: [0, 2], scale: 1, stem: "s")?.map(\.0) == ["s-page-1.png", "s-page-3.png"])

    let imposed = try #require(PDFDocument(url: url).flatMap {
        ImposedPDFWriter.write($0, result: ImpositionLayoutID.saddleStitch.calculate(totalSourcePages: 3, config: ImpositionConfig()), config: ImpositionConfig())
    })
    #expect(PDFDocument(data: imposed)?.pageCount == 2)
}

@Test func zinePDF() throws {
    let context = try #require(CGContext(data: nil, width: 4, height: 6, bitsPerComponent: 8, bytesPerRow: 0,
                                         space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
    let image = try #require(context.makeImage())
    let layout = ZineFold.accordion.layout(panels: 4, doubleSided: true, split: false)
    let data = try #require(ZineFold.pdf(layout: layout, images: [(image, false), nil, (image, true)], paperMm: CGSize(width: 210, height: 297)))
    let page = try #require(PDFDocument(data: data)?.page(at: 0))
    #expect(PDFDocument(data: data)?.pageCount == 2 && page.bounds(for: .mediaBox).width > page.bounds(for: .mediaBox).height)
}
