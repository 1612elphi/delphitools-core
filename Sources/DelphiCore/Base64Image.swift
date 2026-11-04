import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// One image file as Base64 for the encoder: the raw string, its data URI and a thumbnail for the mosaic.
public struct Base64Image: Sendable {
    public enum Rejection: Error { case notImage, tooLarge(Int) }

    public let id = UUID()
    public let name: String
    public let mime: String
    public let bytes: Int
    public let raw: String
    public let thumbnail: CGImage?

    public var dataURI: String { "data:\(mime);base64,\(raw)" }
    public var uriBytes: Int { "data:\(mime);base64,".utf8.count + raw.utf8.count }

    /// The head of the data URI; the whole string stalls text layout.
    public var preview: String {
        let head = "data:\(mime);base64,\(raw.prefix(480))"
        return raw.utf8.count > 480 ? head + "…" : head
    }

    public static func size(_ bytes: Int) -> String { ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file) }

    public static func load(_ url: URL, limit: Int) -> Result<Base64Image, Rejection> {
        let type = UTType(filenameExtension: url.pathExtension)
        guard type?.conforms(to: .image) == true, let mime = type?.preferredMIMEType else { return .failure(.notImage) }
        let bytes = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard bytes <= limit else { return .failure(.tooLarge(bytes)) }
        guard let data = try? Data(contentsOf: url) else { return .failure(.notImage) }
        let thumbnail = CGImageSourceCreateWithData(data as CFData, nil).flatMap {
            CGImageSourceCreateThumbnailAtIndex($0, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 240,
            ] as CFDictionary)
        }
        return .success(Base64Image(name: url.lastPathComponent, mime: mime, bytes: data.count, raw: data.base64EncodedString(), thumbnail: thumbnail))
    }

    /// Characters of a `columns` by `rows` grid that a picture of `picture` covers, its aspect kept, centred.
    public static func cover(columns: Int, rows: Int, cell: CGSize, picture: CGSize) -> (x: Int, y: Int, columns: Int, rows: Int) {
        guard picture.width > 0, picture.height > 0 else { return (0, 0, 0, 0) }
        let area = CGSize(width: CGFloat(columns) * cell.width, height: CGFloat(rows) * cell.height)
        let scale = min(area.width / picture.width, area.height / picture.height)
        let wide = min(columns, max(1, Int((picture.width * scale / cell.width).rounded())))
        let tall = min(rows, max(1, Int((picture.height * scale / cell.height).rounded())))
        return ((columns - wide) / 2, (rows - tall) / 2, wide, tall)
    }

    /// A byte count as a figure and its unit, in binary steps as the web tool shows it.
    public static func figure(_ bytes: Int) -> (String, String) {
        switch bytes {
        case ..<1024: ("\(bytes)", "B")
        case ..<(1024 * 1024): (String(format: "%.1f", Double(bytes) / 1024), "KB")
        default: (String(format: "%.1f", Double(bytes) / 1_048_576), "MB")
        }
    }

    #if DEBUG
    public static func selfCheck() {
        let cell = CGSize(width: 5, height: 10)
        assert(cover(columns: 40, rows: 10, cell: cell, picture: CGSize(width: 100, height: 100)) == (10, 0, 20, 10))
        assert(cover(columns: 40, rows: 10, cell: cell, picture: CGSize(width: 400, height: 50)) == (0, 3, 40, 3))
        assert(figure(512) == ("512", "B") && figure(2048) == ("2.0", "KB") && figure(3 * 1_048_576) == ("3.0", "MB"))
    }
    #endif
}
