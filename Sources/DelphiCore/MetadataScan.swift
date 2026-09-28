import CoreGraphics
import Foundation
import ImageIO

/// Which blocks of metadata a file carries, and where it says it was taken. Structural tags that ImageIO writes into
/// every file (pixel size, resolution, colour space) do not count.
public struct MetadataScan: Equatable, Sendable {
    public enum Block: Int, CaseIterable, Sendable {
        case exif, gps, tiff, iptc, xmp, maker, icc, c2pa

        public var name: String {
            ["EXIF", "GPS", "TIFF", "IPTC", "XMP", "MakerNote", "ICC", "C2PA"][rawValue]
        }
    }

    public struct Location: Equatable, Sendable {
        public var latitude: Double
        public var longitude: Double

        public init(latitude: Double, longitude: Double) {
            self.latitude = latitude
            self.longitude = longitude
        }
    }

    public var blocks: Set<Block> = []
    public var location: Location?

    // imageio writes these always
    public static let structural: Set<String> = [
        "ColorSpace", "PixelXDimension", "PixelYDimension", "Orientation", "TileLength", "TileWidth",
        "XResolution", "YResolution", "ResolutionUnit", "InterlaceType", "XPixelsPerMeter", "YPixelsPerMeter",
        "Gamma", "Chromaticities", "sRGBIntent", "ExifVersion", "FlashPixVersion", "ComponentsConfiguration",
        "YCbCrPositioning", "SceneCaptureType",
    ]

    public init() {}

    /// The blocks and location of the image file `data`.
    public init(_ data: Data) {
        let properties = CGImageSourceCreateWithData(data as CFData, nil)
            .flatMap { CGImageSourceCopyPropertiesAtIndex($0, 0, nil) as? [CFString: Any] } ?? [:]
        func telling(_ key: CFString) -> Bool {
            let names = (properties[key] as? [CFString: Any] ?? [:]).keys.map { $0 as String }
            return !Set(names).isSubset(of: Self.structural)
        }
        if telling(kCGImagePropertyExifDictionary) || properties[kCGImagePropertyExifAuxDictionary] != nil { blocks.insert(.exif) }
        let gps = properties[kCGImagePropertyGPSDictionary] as? [CFString: Any] ?? [:]
        if !gps.isEmpty { blocks.insert(.gps) }
        if telling(kCGImagePropertyTIFFDictionary) { blocks.insert(.tiff) }
        if properties[kCGImagePropertyIPTCDictionary] != nil { blocks.insert(.iptc) }
        if MetadataStripEngine.hasXMP(data) { blocks.insert(.xmp) }
        if properties.keys.contains(where: { ($0 as String).hasPrefix("{Maker") }) { blocks.insert(.maker) }
        // acsp: icc header magic
        if MetadataStripEngine.contains(data, "acsp") { blocks.insert(.icc) }
        if MetadataStripEngine.contains(data, "jumb") && MetadataStripEngine.contains(data, "c2pa") { blocks.insert(.c2pa) }

        if let latitude = gps[kCGImagePropertyGPSLatitude] as? Double, let longitude = gps[kCGImagePropertyGPSLongitude] as? Double {
            let south = (gps[kCGImagePropertyGPSLatitudeRef] as? String) == "S"
            let west = (gps[kCGImagePropertyGPSLongitudeRef] as? String) == "W"
            location = Location(latitude: south ? -latitude : latitude, longitude: west ? -longitude : longitude)
        }
    }

    /// `location` in degrees to four places, with hemisphere letters.
    public static func label(_ location: Location) -> String {
        String(
            format: "%.4f° %@, %.4f° %@",
            abs(location.latitude), location.latitude < 0 ? "S" : "N",
            abs(location.longitude), location.longitude < 0 ? "W" : "E"
        )
    }
}
