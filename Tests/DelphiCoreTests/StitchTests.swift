import CoreGraphics
import Foundation
import Testing
@testable import DelphiCore

private func blank(_ width: Int, _ height: Int) -> CGImage {
    CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
              space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!.makeImage()!
}

@Test func stitchLayout() throws {
    let base = StitchSource(image: blank(1000, 500))
    let square = StitchSource(image: blank(500, 500))
    let sources = [base.id: base, square.id: square]
    let row = StitchNode.leaf(srcID: base.id).wrapping(key: nil, side: .right, adding: [.leaf(srcID: square.id, fit: .match)])
    let layout = try #require(StitchLayoutEngine.layout(root: row, sources: sources, baseID: base.id))
    #expect(layout.size == CGSize(width: 2000, height: 500) && layout.seams.count == 1)
    #expect(layout.ops[1].source == CGRect(x: 0, y: 125, width: 500, height: 250))
    let moved = row.movingLeaf(row.leafKey(ofSource: square.id)!, toSide: .bottom, of: row.leafKey(ofSource: base.id)!)
    #expect(StitchLayoutEngine.layout(root: moved, sources: sources, baseID: base.id)?.size == CGSize(width: 1000, height: 1000))
    #expect(row.removingLeaf(row.leafKey(ofSource: square.id)!)?.leafSrcIDs == [base.id])
    #expect(StitchLayoutEngine.exportSize(CGSize(width: 32768, height: 1000.4)) == CGSize(width: 16384, height: 500))
    // 16000 × 16000 is 256 MP: the area cap halves both sides
    #expect(StitchLayoutEngine.exportSize(CGSize(width: 16000, height: 16000)) == CGSize(width: 8000, height: 8000))
    #expect(StitchLayoutEngine.batchLayout([base, square, square, base, base])?.size == CGSize(width: 3000, height: 1000))
}

@Test func stitchRender() throws {
    func solid(_ red: CGFloat, _ blue: CGFloat, _ width: Int, _ height: Int) -> CGImage {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(srgbRed: red, green: 0, blue: blue, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        // a green top row, to catch a flipped draw
        context.setFillColor(CGColor(srgbRed: 0, green: 1, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: height - 1, width: width, height: 1))
        return context.makeImage()!
    }
    let top = StitchSource(image: solid(1, 0, 20, 10))
    let bottom = StitchSource(image: solid(0, 1, 20, 10))
    let column = StitchNode.leaf(srcID: top.id).wrapping(key: nil, side: .bottom, adding: [.leaf(srcID: bottom.id)])
    let layout = try #require(StitchLayoutEngine.layout(root: column, sources: [top.id: top, bottom.id: bottom], baseID: top.id))
    let image = try #require(StitchLayoutEngine.render(layout, opaque: true))
    #expect(image.width == 20 && image.height == 20)
    let context = try #require(CGContext(data: nil, width: 20, height: 20, bitsPerComponent: 8, bytesPerRow: 80,
                                         space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.draw(image, in: CGRect(x: 0, y: 0, width: 20, height: 20))
    let bytes = try #require(context.data).bindMemory(to: UInt8.self, capacity: 1600)
    // rows from the top of the picture
    let pixel = { (x: Int, y: Int) in (bytes[(y * 20 + x) * 4], bytes[(y * 20 + x) * 4 + 1], bytes[(y * 20 + x) * 4 + 2]) }
    #expect(pixel(5, 0) == (0, 255, 0) && pixel(5, 5) == (255, 0, 0), "top image upright, on top")
    #expect(pixel(5, 10) == (0, 255, 0) && pixel(5, 15) == (0, 0, 255), "bottom image upright, below")
}
