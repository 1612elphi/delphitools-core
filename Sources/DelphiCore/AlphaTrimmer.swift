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
        var pixels = [UInt8](repeating: 0, count: width * height * bytesPerPixel)
        guard let context = CGContext(
            data: &pixels,
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

        var minX = width
        var minY = height
        var maxX = -1
        var maxY = -1

        for y in 0..<height {
            let rowOffset = y * bytesPerRow
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
