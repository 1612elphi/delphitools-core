import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins

/// Colour noise laid over artwork with an overlay blend, and the magnified centre square the tool compares.
public enum ArtworkNoise {
    /// - Parameters:
    ///   - alpha: noise opacity, 0...1.
    ///   - scale: noise block side in pixels, 1...4.
    public static func enhance(_ source: CGImage, alpha: CGFloat, scale: Int, seed: Int, context: CIContext) -> CGImage? {
        let sourceCI = CIImage(cgImage: source)
        let extent = sourceCI.extent
        let matrix = CIFilter.colorMatrix()
        matrix.inputImage = noise(for: extent, seed: seed, scale: scale)
        matrix.rVector = CIVector(x: 1, y: 0, z: 0, w: 0)
        matrix.gVector = CIVector(x: 0, y: 1, z: 0, w: 0)
        matrix.bVector = CIVector(x: 0, y: 0, z: 1, w: 0)
        matrix.aVector = CIVector(x: 0, y: 0, z: 0, w: alpha)
        matrix.biasVector = CIVector(x: 0, y: 0, z: 0, w: 0)
        let composite = CIFilter.overlayBlendMode()
        composite.inputImage = matrix.outputImage
        composite.backgroundImage = sourceCI
        return composite.outputImage.flatMap { context.createCGImage($0, from: extent) }
    }

    /// Hard-edged blocks of `scale` pixels, as the web tool draws them.
    public static func noise(for extent: CGRect, seed: Int, scale: Int) -> CIImage {
        let noise = CIFilter.randomGenerator().outputImage!
            .transformed(by: CGAffineTransform(translationX: CGFloat(seed * 100), y: CGFloat(seed * 73)))
        guard scale > 1 else { return noise.cropped(to: extent) }
        let side = CGFloat(scale)
        let small = CGRect(x: extent.origin.x, y: extent.origin.y, width: extent.width / side, height: extent.height / side)
        // linear sampling blurs blocks
        return noise.cropped(to: small).samplingNearest().transformed(by: CGAffineTransform(scaleX: side, y: side)).cropped(to: extent)
    }

    /// The centred square of at most `side` pixels, top-left origin.
    public static func detailRect(in size: CGSize, side: Int) -> CGRect {
        let edge = CGFloat(min(side, Int(size.width), Int(size.height)))
        return CGRect(x: ((size.width - edge) / 2).rounded(.down), y: ((size.height - edge) / 2).rounded(.down), width: edge, height: edge)
    }

    /// The centred square, each pixel drawn `factor` times wider without smoothing.
    public static func magnified(_ image: CGImage, side: Int, factor: Int) -> CGImage? {
        let rect = detailRect(in: CGSize(width: image.width, height: image.height), side: side)
        let out = Int(rect.width) * factor
        guard out > 0, let crop = image.cropping(to: rect),
              let context = CGContext(data: nil, width: out, height: out, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.interpolationQuality = .none
        context.draw(crop, in: CGRect(x: 0, y: 0, width: out, height: out))
        return context.makeImage()
    }

    #if DEBUG
    public static func selfCheck() {
        assert(detailRect(in: CGSize(width: 200, height: 100), side: 64) == CGRect(x: 68, y: 18, width: 64, height: 64))
        assert(detailRect(in: CGSize(width: 40, height: 30), side: 64) == CGRect(x: 5, y: 0, width: 30, height: 30))
        let context = CIContext(options: [.workingColorSpace: NSNull()])
        let square = CGRect(x: 0, y: 0, width: 8, height: 8)
        guard let cg = context.createCGImage(noise(for: square, seed: 3, scale: 2), from: square, format: .RGBA8,
                                             colorSpace: CGColorSpace(name: CGColorSpace.sRGB)),
              let bytes = cg.dataProvider?.data.flatMap({ CFDataGetBytePtr($0) }) else { return assertionFailure("noise render") }
        let pixel = { (x: Int, y: Int, image: CGImage, data: UnsafePointer<UInt8>) in (0..<3).map { data[y * image.bytesPerRow + x * 4 + $0] } }
        for block in [(0, 0), (2, 4), (6, 6)] {
            let first = pixel(block.0, block.1, cg, bytes)
            assert([(1, 0), (0, 1), (1, 1)].allSatisfy { pixel(block.0 + $0.0, block.1 + $0.1, cg, bytes) == first }, "noise block")
        }
        assert(pixel(0, 0, cg, bytes) != pixel(2, 0, cg, bytes) || pixel(0, 0, cg, bytes) != pixel(0, 2, cg, bytes), "blocks differ")
        guard let big = magnified(cg, side: 4, factor: 3), let data = big.dataProvider?.data.flatMap({ CFDataGetBytePtr($0) }) else {
            return assertionFailure("magnify")
        }
        assert(big.width == 12 && big.height == 12)
        assert(pixel(0, 0, big, data) == pixel(2, 2, big, data) && pixel(3, 0, big, data) == pixel(5, 2, big, data))
        assert(enhance(cg, alpha: 0.1, scale: 1, seed: 0, context: context)?.width == 8)
    }
    #endif
}
