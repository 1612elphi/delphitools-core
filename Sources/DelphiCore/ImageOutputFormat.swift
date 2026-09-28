import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// The formats the image converter writes.
public enum ImageOutputFormat: String, CaseIterable, Sendable {
    case png, jpeg, heic, bmp, tiff, gif

    public var label: String { rawValue.uppercased() }

    public var utType: UTType {
        switch self {
        case .png: .png
        case .jpeg: .jpeg
        case .heic: .heic
        case .bmp: .bmp
        case .tiff: .tiff
        case .gif: .gif
        }
    }

    public var fileExtension: String { self == .jpeg ? "jpg" : rawValue }

    public var supportsQuality: Bool { self == .jpeg || self == .heic }

    public var supportsTransparency: Bool { self == .png || self == .tiff || self == .gif }

    /// `image` redrawn at `width` × `height` when that is not its size, over `flatten` when it is set, and encoded;
    /// nil when ImageIO cannot write it. `quality`, 0...1, applies to JPEG and HEIC.
    public func encode(_ image: CGImage, width: Int, height: Int, quality: Double, flatten: CGColor?) -> Data? {
        var image = image
        if width != image.width || height != image.height || flatten != nil {
            let space = image.colorSpace.flatMap { $0.model == .rgb ? $0 : nil } ?? CGColorSpace(name: CGColorSpace.sRGB)!
            let alpha = flatten == nil ? CGImageAlphaInfo.premultipliedLast : .noneSkipLast
            guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                          space: space, bitmapInfo: alpha.rawValue)
            else { return nil }
            let bounds = CGRect(x: 0, y: 0, width: width, height: height)
            if let flatten {
                context.setFillColor(flatten)
                context.fill(bounds)
            }
            context.interpolationQuality = .high
            context.draw(image, in: bounds)
            guard let drawn = context.makeImage() else { return nil }
            image = drawn
        }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, utType.identifier as CFString, 1, nil) else { return nil }
        let options = supportsQuality ? [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary : nil
        CGImageDestinationAddImage(destination, image, options)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }
}
