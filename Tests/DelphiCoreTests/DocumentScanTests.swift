import CoreGraphics
import Foundation
import PDFKit
import Testing
@testable import DelphiCore

@Test func documentScan() throws {
    let cell = { (text: String, x: CGFloat, y: CGFloat) in DocumentScanText.Line(text: text, box: CGRect(x: x, y: y, width: 0.2, height: 0.02), confidence: 1) }
    let table = [cell("Proof set", 0.1, 0.40), cell("Saddle", 0.1, 0.30), cell("2", 0.6, 0.401), cell("200", 0.6, 0.302), cell("Total", 0.1, 0.6)]
    #expect(DocumentScanText.text(table) == "Saddle\t200\nProof set\t2\nTotal")
    #expect(DocumentScanText.readingOrder(table).map(\.text) == ["Saddle", "200", "Proof set", "2", "Total"])
    #expect(DocumentScanText.pageSize(pixels: CGSize(width: 1240, height: 1754)) == CGSize(width: 595, height: 842))
    #expect(DocumentScanText.pageSize(pixels: CGSize(width: 3000, height: 1500)) == CGSize(width: 842, height: 421))

    let context = try #require(CGContext(data: nil, width: 300, height: 400, bitsPerComponent: 8, bytesPerRow: 0,
                                         space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
    context.setFillColor(CGColor(gray: 1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: 300, height: 400))
    let image = try #require(context.makeImage())
    let line = DocumentScanText.Line(text: "Delphi scan", box: CGRect(x: 0.1, y: 0.2, width: 0.5, height: 0.05), confidence: 1)
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("scan-test-\(UUID().uuidString).pdf")
    defer { try? FileManager.default.removeItem(at: url) }
    try DocumentScanPDF.write([(image, [line])], to: url, progress: { _ in })
    let document = try #require(PDFDocument(url: url))
    let page = try #require(document.page(at: 0))
    #expect(document.string?.contains("Delphi scan") == true)
    let found = document.findString("Delphi", withOptions: []).first?.bounds(for: page) ?? .zero
    let size = page.bounds(for: .mediaBox).size
    #expect(abs(found.minX - 0.1 * size.width) < 3, "\(found)")
    #expect(abs(found.midY - (1 - 0.225) * size.height) < 4, "\(found)")
}
