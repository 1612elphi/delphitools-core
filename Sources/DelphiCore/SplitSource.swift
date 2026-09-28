import CoreGraphics
import Foundation
import ImageIO

/// An image file decoded for the image tools: a working copy and a preview, both upright.
public struct SplitSource: Sendable {
    public let image: CGImage
    public let preview: CGImage
    /// The file's own pixel size, upright; `image` is smaller when the file exceeds `maxPixels`.
    public let pixels: (width: Int, height: Int)
    public let name: String

    public var stem: String {
        let base = (name as NSString).deletingPathExtension
        return base.isEmpty ? "image" : base
    }

    /// The image at `url` decoded upright, no side over `maxPixels`, and a preview no side over `previewPixels`.
    public static func decode(_ url: URL, maxPixels: Int, previewPixels: Int = 1600) -> SplitSource? {
        guard let file = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        func thumbnail(_ pixels: Int) -> CGImage? {
            CGImageSourceCreateThumbnailAtIndex(file, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: pixels,
            ] as CFDictionary)
        }
        guard let image = thumbnail(maxPixels), let preview = thumbnail(previewPixels) else { return nil }
        let properties = CGImageSourceCopyPropertiesAtIndex(file, 0, nil) as? [CFString: Any]
        var width = properties?[kCGImagePropertyPixelWidth] as? Int ?? image.width
        var height = properties?[kCGImagePropertyPixelHeight] as? Int ?? image.height
        // exif 5...8 swap axes
        if let turn = properties?[kCGImagePropertyOrientation] as? Int, turn >= 5 { swap(&width, &height) }
        return SplitSource(image: image, preview: preview, pixels: (width, height), name: url.lastPathComponent)
    }
}
