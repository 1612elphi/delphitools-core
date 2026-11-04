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

/// An image cut into a grid of equal tiles.
public enum ImageSplitEngine {
    public struct Cell: Equatable, Sendable {
        public let row: Int
        public let column: Int

        public init(row: Int, column: Int) {
            (self.row, self.column) = (row, column)
        }

        /// `row-column`, counted from 1, as the web tool names the files.
        public var label: String { "\(row + 1)-\(column + 1)" }
    }

    /// Whole pixels per tile; the remainder on the trailing and bottom edges is left out.
    public static func tileSize(width: Int, height: Int, rows: Int, columns: Int) -> (width: Int, height: Int) {
        (width / max(1, columns), height / max(1, rows))
    }

    public static func cells(rows: Int, columns: Int) -> [Cell] {
        (0..<rows).flatMap { row in (0..<columns).map { Cell(row: row, column: $0) } }
    }

    /// The cell's crop in image pixels, top-left origin.
    public static func rect(_ cell: Cell, width: Int, height: Int, rows: Int, columns: Int) -> CGRect {
        let size = tileSize(width: width, height: height, rows: rows, columns: columns)
        return CGRect(x: cell.column * size.width, y: cell.row * size.height, width: size.width, height: size.height)
    }

    #if DEBUG
    public static func selfCheck() {
        assert(tileSize(width: 1000, height: 601, rows: 3, columns: 3) == (333, 200))
        assert(cells(rows: 2, columns: 3).count == 6 && cells(rows: 2, columns: 3)[4] == Cell(row: 1, column: 1))
        assert(rect(Cell(row: 1, column: 2), width: 1000, height: 600, rows: 3, columns: 3) == CGRect(x: 666, y: 200, width: 333, height: 200))
        assert(Cell(row: 0, column: 9).label == "1-10")
    }
    #endif
}

extension SplitSource {
    public func crop(_ cell: ImageSplitEngine.Cell, rows: Int, columns: Int) -> CGImage? {
        image.cropping(to: ImageSplitEngine.rect(cell, width: image.width, height: image.height, rows: rows, columns: columns))
    }

    /// `<stem>-<row>-<column>.png` and its bytes for each cell, or nil when a tile fails.
    public func pngs(_ cells: [ImageSplitEngine.Cell], rows: Int, columns: Int) -> [(String, Data)]? {
        var files: [(String, Data)] = []
        for cell in cells {
            guard let crop = crop(cell, rows: rows, columns: columns),
                  let data = ImageOutputFormat.png.encode(crop, width: crop.width, height: crop.height, quality: 1, flatten: nil)
            else { return nil }
            files.append(("\(stem)-\(cell.label).png", data))
        }
        return files
    }
}
