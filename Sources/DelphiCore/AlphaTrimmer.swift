import CoreGraphics

public enum AlphaTrimmer {
    /// Returns the smallest rect (in image-pixel coordinates) covering all
    /// pixels with alpha above `threshold`. Nil if the image is fully
    /// transparent or uses an alpha-less colour space.
    public static func boundingRect(of cgImage: CGImage, threshold: UInt8 = 0) -> CGRect? {
        let width = cgImage.width
        let height = cgImage.height
        guard width > 0, height > 0 else { return nil }

        let alphaInfo = cgImage.alphaInfo
        guard alphaInfo != .none, alphaInfo != .noneSkipFirst, alphaInfo != .noneSkipLast else {
            return nil
        }

        // normalise to rgba8 layout
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let data = context.data else { return nil }
        let pixels = data.assumingMemoryBound(to: UInt8.self)

        var minX = width
        var minY = height
        var maxX = -1
        var maxY = -1

        for y in 0..<height {
            let rowOffset = y * context.bytesPerRow
            for x in 0..<width {
                let alpha = pixels[rowOffset + x * bytesPerPixel + 3]
                if alpha > threshold {
                    if x < minX { minX = x }
                    if x > maxX { maxX = x }
                    if y < minY { minY = y }
                    if y > maxY { maxY = y }
                }
            }
        }

        guard maxX >= minX, maxY >= minY else { return nil }
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }
}

/// The transparent edges a clip removes, in pixels, and the share of the area it saves.
public struct ClipMargins: Equatable, Sendable {
    public let top: Int
    public let right: Int
    public let bottom: Int
    public let left: Int
    public let savedPercent: Int

    /// - Parameter kept: top-left origin.
    public init(kept: CGRect, in size: CGSize) {
        top = Int(kept.minY)
        left = Int(kept.minX)
        bottom = Int(size.height - kept.maxY)
        right = Int(size.width - kept.maxX)
        let area = size.width * size.height
        savedPercent = area > 0 ? Int(((1 - kept.width * kept.height / area) * 100).rounded()) : 0
    }

    public var isEmpty: Bool { top == 0 && right == 0 && bottom == 0 && left == 0 }

    #if DEBUG
    public static func selfCheck() {
        let margins = ClipMargins(kept: CGRect(x: 500, y: 250, width: 600, height: 400), in: CGSize(width: 1400, height: 1000))
        assert([margins.top, margins.right, margins.bottom, margins.left, margins.savedPercent] == [250, 300, 350, 500, 83])
        assert(ClipMargins(kept: CGRect(x: 0, y: 0, width: 10, height: 10), in: CGSize(width: 10, height: 10)).isEmpty)
        guard let context = CGContext(data: nil, width: 12, height: 8, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return assertionFailure("context") }
        // bottom-left origin: y 1 is top-left y 5
        context.fill(CGRect(x: 4, y: 1, width: 3, height: 2))
        guard let image = context.makeImage() else { return assertionFailure("render") }
        assert(AlphaTrimmer.boundingRect(of: image) == CGRect(x: 4, y: 5, width: 3, height: 2), "top-left origin, pixel exact")
        context.clear(CGRect(x: 0, y: 0, width: 12, height: 8))
        assert(context.makeImage().flatMap { AlphaTrimmer.boundingRect(of: $0) } == nil, "fully transparent")
    }
    #endif
}
