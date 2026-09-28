import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum MetadataStripEngine {

    public struct Entry: Identifiable, Sendable {
        public let label: String
        public let detail: String
        public var id: String { label + detail }
        public var isLocation: Bool { label == "GPS coordinates" }
    }

    public struct Report: Sendable {
        public var entries: [Entry] = []
        public var hasContentCredentials = false
        public var readable = false

        public init() {}
    }

    public struct StripResult: Sendable {
        public let data: Data
        public let removed: [String]
    }

    // order of removed list; cfstring constants are immutable
    nonisolated(unsafe) private static let strippable: [(key: CFString, label: String)] = [
        (kCGImagePropertyExifDictionary, "EXIF"),
        (kCGImagePropertyGPSDictionary, "GPS"),
        (kCGImagePropertyTIFFDictionary, "TIFF"),
        (kCGImagePropertyIPTCDictionary, "IPTC"),
        (kCGImagePropertyExifAuxDictionary, "Exif aux"),
        (kCGImagePropertyMakerAppleDictionary, "MakerNote"),
    ]

    /// The privacy fields of the image file `data`, labelled for display; `readable` is false when ImageIO cannot open it.
    public static func report(for data: Data) -> Report {
        var report = Report()
        report.hasContentCredentials = contains(data, "jumb") && contains(data, "c2pa")

        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else { return report }

        report.readable = true
        let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
        let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]
        let gps = properties[kCGImagePropertyGPSDictionary] as? [CFString: Any] ?? [:]
        let aux = properties[kCGImagePropertyExifAuxDictionary] as? [CFString: Any] ?? [:]

        var entries: [Entry] = []

        if let coordinate = coordinate(from: gps) {
            entries.append(Entry(label: String(localized: "GPS coordinates"), detail: coordinate))
        }
        if let stamp = gps[kCGImagePropertyGPSDateStamp] as? String {
            entries.append(Entry(label: String(localized: "GPS timestamp"), detail: stamp))
        }

        let camera = [tiff[kCGImagePropertyTIFFMake] as? String, tiff[kCGImagePropertyTIFFModel] as? String]
            .compactMap { $0 }
            .joined(separator: " ")
        if !camera.isEmpty { entries.append(Entry(label: String(localized: "Camera"), detail: camera)) }

        let lens = exif[kCGImagePropertyExifLensModel] as? String ?? aux[kCGImagePropertyExifAuxLensModel] as? String
        if let lens { entries.append(Entry(label: String(localized: "Lens"), detail: lens)) }
        if let serial = exif[kCGImagePropertyExifBodySerialNumber] as? String {
            entries.append(Entry(label: String(localized: "Camera serial"), detail: serial))
        }
        if let serial = exif[kCGImagePropertyExifLensSerialNumber] as? String {
            entries.append(Entry(label: String(localized: "Lens serial"), detail: serial))
        }
        if let owner = exif[kCGImagePropertyExifCameraOwnerName] as? String {
            entries.append(Entry(label: String(localized: "Owner name"), detail: owner))
        }
        if let taken = exif[kCGImagePropertyExifDateTimeOriginal] as? String {
            entries.append(Entry(label: String(localized: "Taken"), detail: taken))
        }
        if let digitised = exif[kCGImagePropertyExifDateTimeDigitized] as? String {
            entries.append(Entry(label: String(localized: "Digitised"), detail: digitised))
        }
        if let modified = tiff[kCGImagePropertyTIFFDateTime] as? String {
            entries.append(Entry(label: String(localized: "Modified"), detail: modified))
        }
        if let software = tiff[kCGImagePropertyTIFFSoftware] as? String {
            entries.append(Entry(label: String(localized: "Software"), detail: software))
        }
        if let artist = tiff[kCGImagePropertyTIFFArtist] as? String {
            entries.append(Entry(label: String(localized: "Artist"), detail: artist))
        }
        if let copyright = tiff[kCGImagePropertyTIFFCopyright] as? String {
            entries.append(Entry(label: String(localized: "Copyright"), detail: copyright))
        }
        if let description = tiff[kCGImagePropertyTIFFImageDescription] as? String {
            entries.append(Entry(label: String(localized: "Description"), detail: description))
        }
        if let comment = exif[kCGImagePropertyExifUserComment] as? String, !comment.isEmpty {
            entries.append(Entry(label: String(localized: "Comment"), detail: comment))
        }
        if properties[kCGImagePropertyMakerAppleDictionary] != nil {
            entries.append(Entry(label: "MakerNote", detail: String(localized: "vendor data present")))
        }
        if properties[kCGImagePropertyIPTCDictionary] != nil {
            entries.append(Entry(label: "IPTC", detail: String(localized: "Photoshop resource block")))
        }
        if hasXMP(data) {
            entries.append(Entry(label: String(localized: "XMP packet"), detail: String(localized: "present")))
        }
        if let profile = properties[kCGImagePropertyProfileName] as? String {
            entries.append(Entry(label: String(localized: "Colour profile"), detail: profile))
        }

        report.entries = entries
        return report
    }

    /// Re-encodes the pixels and writes nothing from the source's metadata
    /// except orientation and resolution. Returns nil for animated or
    /// unwritable formats.
    public static func strip(_ data: Data) -> StripResult? {
        let uncached = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, uncached),
              let type = CGImageSourceGetType(source)
        else { return nil }

        let count = CGImageSourceGetCount(source)
        let animatable = [UTType.gif, .png, .webP].contains { $0.identifier == type as String }
        // one frame loses animation
        guard count > 0, count == 1 || !animatable else { return nil }

        let index = CGImageSourceGetPrimaryImageIndex(source)
        let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any] ?? [:]
        guard let image = CGImageSourceCreateImageAtIndex(source, index, uncached) else { return nil }

        var removed = strippable.filter { properties[$0.key] != nil }.map(\.label)
        let hasVendorNotes = properties.keys.contains { ($0 as String).hasPrefix("{Maker") }
        if hasVendorNotes, !removed.contains("MakerNote") { removed.append("MakerNote") }
        if hasXMP(data) { removed.append("XMP") }

        // ponytail: lossy formats are recompressed; a JPEG segment stripper as the web's stripJpeg would be lossless
        var kept: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: 0.9]
        // baking needs second bitmap
        for key in [kCGImagePropertyOrientation, kCGImagePropertyDPIWidth, kCGImagePropertyDPIHeight] {
            kept[key] = properties[key]
        }

        let out = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(out, type, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, kept as CFDictionary)
        guard CGImageDestinationFinalize(destination), out.length > 0 else { return nil }

        return StripResult(data: out as Data, removed: removed)
    }

    /// Whether `data` holds an XMP packet; read from the bytes, as ImageIO synthesises XMP tags for every file.
    public static func hasXMP(_ data: Data) -> Bool {
        contains(data, "<x:xmpmeta") || contains(data, "<rdf:RDF")
    }

    private static func coordinate(from gps: [CFString: Any]) -> String? {
        guard let latitude = gps[kCGImagePropertyGPSLatitude] as? Double,
              let longitude = gps[kCGImagePropertyGPSLongitude] as? Double
        else { return nil }
        let latitudeRef = gps[kCGImagePropertyGPSLatitudeRef] as? String ?? "N"
        let longitudeRef = gps[kCGImagePropertyGPSLongitudeRef] as? String ?? "E"
        var text = String(format: "%.6f° %@, %.6f° %@", latitude, latitudeRef, longitude, longitudeRef)
        if let altitude = gps[kCGImagePropertyGPSAltitude] as? Double {
            let below = (gps[kCGImagePropertyGPSAltitudeRef] as? Int) == 1
            text = String(localized: "\(text) · alt \(Int((below ? -altitude : altitude).rounded())) m")
        }
        return text
    }

    /// Whether `marker`'s UTF-8 bytes occur in `data`.
    public static func contains(_ data: Data, _ marker: String) -> Bool {
        data.range(of: Data(marker.utf8)) != nil
    }
}
