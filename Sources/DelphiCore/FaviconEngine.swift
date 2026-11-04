import CoreGraphics
import Foundation
import ImageIO

public enum FaviconEngine {
    public static let sizes = [16, 32, 48, 64, 128, 180, 192, 512]
    public static let icoSizes: Set = [16, 32, 48, 64]

    /// The web tool's snippet, word for word.
    public static let snippet = """
    <link rel="icon" type="image/png" sizes="16x16" href="/favicon-16x16.png">
    <link rel="icon" type="image/png" sizes="32x32" href="/favicon-32x32.png">
    <link rel="apple-touch-icon" sizes="180x180" href="/favicon-180x180.png">
    <link rel="icon" type="image/png" sizes="192x192" href="/favicon-192x192.png">
    <link rel="icon" type="image/png" sizes="512x512" href="/favicon-512x512.png">
    """

    public struct Icon: Sendable {
        public let size: Int
        public let image: CGImage?
    }

    public static func fileName(_ size: Int) -> String { "favicon-\(size)x\(size).png" }

    /// What a size is for, where it has a name.
    public static func role(_ size: Int) -> String? {
        switch size {
        case 180: "Apple Touch"
        case 192: "Android"
        case 512: "PWA"
        case _ where icoSizes.contains(size): "ICO"
        default: nil
        }
    }

    /// Smallest crop: a tenth of the short side, never under one pixel per pixel of the 16 px icon.
    public static func minimumSide(width: Int, height: Int) -> Int { max(16, min(width, height) / 10) }

    /// A square of `side` pixels in the middle of the image; nil takes the largest.
    public static func centred(width: Int, height: Int, side: Int? = nil) -> CGRect {
        let full = min(width, height)
        let side = side ?? full
        return clamp(CGRect(x: (width - side) / 2, y: (height - side) / 2, width: side, height: side), width: width, height: height)
    }

    /// `square` in whole pixels, square, at least `minimumSide` (or the whole short side of a smaller image), inside the image.
    public static func clamp(_ square: CGRect, width: Int, height: Int) -> CGRect {
        let full = min(width, height)
        let side = min(max(Int(square.width.rounded()), min(minimumSide(width: width, height: height), full)), full)
        let x = min(max(Int(square.minX.rounded()), 0), width - side)
        let y = min(max(Int(square.minY.rounded()), 0), height - side)
        return CGRect(x: x, y: y, width: side, height: side)
    }

    public static func render(_ image: CGImage, square: CGRect) -> [Icon] {
        guard let cropped = image.cropping(to: square) else { return [] }
        return sizes.map { size in
            autoreleasepool {
                guard let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                                              space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
                else { return Icon(size: size, image: nil) }
                context.interpolationQuality = .high
                context.draw(cropped, in: CGRect(x: 0, y: 0, width: size, height: size))
                return Icon(size: size, image: context.makeImage())
            }
        }
    }

    /// An ICO file of PNG frames, smallest first; a size of 256 or more is written as 0, as the format asks.
    public static func ico(_ frames: [(size: Int, png: Data)]) -> Data {
        let ordered = frames.sorted { $0.size < $1.size }
        var data = Data()
        func put16(_ value: Int) { data.append(contentsOf: [UInt8(value & 0xFF), UInt8(value >> 8 & 0xFF)]) }
        func put32(_ value: Int) { put16(value & 0xFFFF); put16(value >> 16 & 0xFFFF) }
        put16(0)
        // icon type
        put16(1)
        put16(ordered.count)
        var offset = 6 + 16 * ordered.count
        for frame in ordered {
            let side = frame.size < 256 ? frame.size : 0
            data.append(contentsOf: [UInt8(side), UInt8(side), 0, 0])
            // planes, bits per pixel
            put16(1)
            put16(32)
            put32(frame.png.count)
            put32(offset)
            offset += frame.png.count
        }
        ordered.forEach { data.append($0.png) }
        return data
    }

    #if DEBUG
    public static func selfCheck() {
        assert(centred(width: 400, height: 200) == CGRect(x: 100, y: 0, width: 200, height: 200))
        assert(centred(width: 400, height: 200, side: 100) == CGRect(x: 150, y: 50, width: 100, height: 100))
        assert(clamp(CGRect(x: 350, y: -20, width: 90, height: 90), width: 400, height: 200) == CGRect(x: 310, y: 0, width: 90, height: 90))
        assert(clamp(CGRect(x: 10, y: 10, width: 3, height: 3), width: 400, height: 200) == CGRect(x: 10, y: 10, width: 20, height: 20))
        assert(clamp(CGRect(x: 0, y: 0, width: 3, height: 3), width: 100, height: 100).width == 16)
        assert(clamp(CGRect(x: 0, y: 0, width: 900, height: 900), width: 400, height: 200).width == 200)
        assert(clamp(CGRect(x: 0, y: 0, width: 1, height: 1), width: 10, height: 8).width == 8)
        let file = ico([(size: 32, png: Data([9, 9])), (size: 16, png: Data([7]))])
        assert(Array(file.prefix(6)) == [0, 0, 1, 0, 2, 0])
        // first entry at 38
        assert(Array(file[6..<22]) == [16, 16, 0, 0, 1, 0, 32, 0, 1, 0, 0, 0, 38, 0, 0, 0])
        assert(file[22] == 32 && file[34] == 39 && Array(file.suffix(3)) == [7, 9, 9])
        assert(ico([(size: 256, png: Data([1]))])[6] == 0)
    }
    #endif
}

public struct FaviconSource: Sendable {
    public let image: CGImage
    public let preview: CGImage
    public let name: String

    public var width: Int { image.width }
    public var height: Int { image.height }
    public var stem: String {
        let base = (name as NSString).deletingPathExtension
        return base.isEmpty ? "image" : base
    }

    /// The largest favicon is 512 px, so the short side needs no more; 2048 on the long side covers a 4:1 image.
    public static func load(_ url: URL) -> FaviconSource? {
        guard let file = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        func decode(_ pixels: Int) -> CGImage? {
            CGImageSourceCreateThumbnailAtIndex(file, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: pixels,
            ] as CFDictionary)
        }
        guard let image = decode(2048), let preview = decode(800) else { return nil }
        return FaviconSource(image: image, preview: preview, name: url.lastPathComponent)
    }
}
