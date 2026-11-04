import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum ImageCompressFormat: String, CaseIterable, Sendable {
    case jpeg, png, heic

    public var label: String { rawValue.uppercased() }

    public var utType: UTType {
        switch self {
        case .jpeg: .jpeg
        case .png: .png
        case .heic: .heic
        }
    }

    public var fileExtension: String { self == .jpeg ? "jpg" : rawValue }

    public var hasQuality: Bool { self != .png }

    public var isOpaque: Bool { self == .jpeg }

    /// The formats this Mac has an encoder for.
    public static let available: [ImageCompressFormat] = {
        let writable = CGImageDestinationCopyTypeIdentifiers() as? [String] ?? []
        return allCases.filter { writable.contains($0.utType.identifier) }
    }()
}

public enum ImageCompressEngine {
    /// - Parameters:
    ///   - quality: 1...100.
    ///   - orientation: EXIF orientation, written as a tag.
    public static func encode(_ image: CGImage, format: ImageCompressFormat, quality: Double, orientation: Int = 1) -> Data? {
        let source = format.isOpaque ? flattened(image, on: CGColor(gray: 1, alpha: 1)) ?? image : image
        let out = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(out, format.utType.identifier as CFString, 1, nil) else { return nil }
        var options: [CFString: Any] = [kCGImagePropertyOrientation: orientation]
        if format.hasQuality { options[kCGImageDestinationLossyCompressionQuality] = min(1, max(0.01, quality / 100)) }
        CGImageDestinationAddImage(destination, source, options as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return out as Data
    }

    /// The primary image, not yet decoded, and its EXIF orientation.
    public static func decode(_ data: Data) -> (image: CGImage, orientation: Int)? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let index = CGImageSourceGetPrimaryImageIndex(source)
        guard let image = CGImageSourceCreateImageAtIndex(source, index, nil) else { return nil }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]
        return (image, properties?[kCGImagePropertyOrientation] as? Int ?? 1)
    }

    /// Upright, no side over `maxPixels`, without decoding the full bitmap.
    public static func thumbnail(of data: Data, maxPixels: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, CGImageSourceGetPrimaryImageIndex(source), options as CFDictionary)
    }

    /// Size change as a whole percentage of `before`: negative is smaller.
    public static func savingsPercent(before: Int, after: Int) -> Int {
        guard before > 0 else { return 0 }
        return Int((Double(after - before) / Double(before) * 100).rounded())
    }

    public static func savingsLabel(before: Int, after: Int) -> String {
        let savings = savingsPercent(before: before, after: after)
        if savings == 0 { return "±0%" }
        return "\(savings < 0 ? "−" : "+")\(abs(savings))%"
    }

    /// `image` drawn over `colour`; an image without alpha comes back as it is.
    public static func flattened(_ image: CGImage, on colour: CGColor) -> CGImage? {
        guard ![.none, .noneSkipFirst, .noneSkipLast].contains(image.alphaInfo) else { return image }
        let space = image.colorSpace.flatMap { $0.model == .rgb && $0.supportsOutput ? $0 : nil } ?? CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        context.setFillColor(colour)
        context.fill(rect)
        context.draw(image, in: rect)
        return context.makeImage()
    }

    #if DEBUG
    public static func selfCheck() {
        assert(savingsPercent(before: 1000, after: 400) == -60 && savingsPercent(before: 1000, after: 1500) == 50)
        assert(savingsPercent(before: 0, after: 100) == 0)
        assert(savingsLabel(before: 1000, after: 1000) == "±0%" && savingsLabel(before: 1000, after: 400) == "−60%")
        // alpha flattens to white
        guard let context = CGContext(data: nil, width: 4, height: 2, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let clear = context.makeImage(),
              let jpeg = encode(clear, format: .jpeg, quality: 90, orientation: 6),
              let decoded = decode(jpeg)
        else { return assertionFailure("jpeg round trip failed") }
        assert(decoded.orientation == 6)
        assert(thumbnail(of: jpeg, maxPixels: 4).map { $0.width == 2 && $0.height == 4 } == true)
        var pixel = [UInt8](repeating: 0, count: 4)
        let probe = CGContext(data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                              space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        probe?.draw(decoded.image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        assert(pixel[0] > 250 && pixel[1] > 250 && pixel[2] > 250)
        assert(ImageCompressFormat.available.contains(.jpeg) && ImageCompressFormat.available.contains(.png))
    }
    #endif
}
