import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum ImageAtlasReport {

    public struct Row: Identifiable, Sendable {
        public let label: String
        public let value: String
        public var id: String { label }

        public init(label: String, value: String) {
            self.label = label
            self.value = value
        }
    }

    public struct Section: Identifiable, Sendable {
        public let title: String
        public let rows: [Row]
        public var id: String { title }

        public init(title: String, rows: [Row]) {
            self.title = title
            self.rows = rows
        }

        public var localizedTitle: String {
            switch title {
            case "File": String(localized: "File")
            case "Colour": String(localized: "Colour")
            case "Camera": String(localized: "Camera")
            case "Capture": String(localized: "Capture")
            case "Image": String(localized: "Image")
            case "Location": String(localized: "Location")
            case "Dates": String(localized: "Dates")
            case "Other": String(localized: "Other")
            default: title
            }
        }
    }

    public struct Atlas: Sendable {
        public var sections: [Section] = []
        public var coordinate: (latitude: Double, longitude: Double)?
        public var fieldCount = 0
        public var readable = false
        public var hasAlpha = false
        /// Compass bearing the camera faced, 0 north, clockwise.
        public var heading: Double?
        public var byteCount = 0
        /// Short type name, `JPEG`.
        public var format: String?
        public var profile: String?
    }

    /// The file's metadata in sections for display; `readable` is false when ImageIO cannot open it.
    public static func build(data: Data, filename: String) -> Atlas {
        var atlas = Atlas()
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else { return atlas }

        atlas.readable = true

        let width = properties[kCGImagePropertyPixelWidth] as? Int
        let height = properties[kCGImagePropertyPixelHeight] as? Int

        var fileRows: [Row] = [
            Row(label: String(localized: "File Name"), value: filename),
            Row(label: String(localized: "File Size"), value: ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file)),
        ]
        atlas.byteCount = data.count
        if let type = CGImageSourceGetType(source) as String?,
           let utType = UTType(type) {
            fileRows.append(Row(label: String(localized: "MIME Type"), value: utType.preferredMIMEType ?? type))
            atlas.format = utType.preferredFilenameExtension?.uppercased()
        }
        if let width, let height {
            fileRows.append(Row(label: String(localized: "Dimensions"), value: "\(width) × \(height)"))
        }
        if let dpi = properties[kCGImagePropertyDPIWidth] as? Double {
            fileRows.append(Row(label: String(localized: "Resolution"), value: "\(Int(dpi.rounded())) dpi"))
        }
        atlas.sections.append(Section(title: "File", rows: fileRows))

        var colourRows: [Row] = []
        if let model = properties[kCGImagePropertyColorModel] as? String {
            colourRows.append(Row(label: String(localized: "Colour Model"), value: model))
        }
        if let profile = properties[kCGImagePropertyProfileName] as? String {
            atlas.profile = profile
            colourRows.append(Row(label: String(localized: "Colour Profile"), value: profile))
        }
        if let depth = properties[kCGImagePropertyDepth] as? Int {
            colourRows.append(Row(label: String(localized: "Bit Depth"), value: String(localized: "\(depth) bits")))
        }
        if let alpha = properties[kCGImagePropertyHasAlpha] as? Bool {
            atlas.hasAlpha = alpha
            colourRows.append(Row(label: String(localized: "Alpha"), value: alpha ? String(localized: "Yes") : String(localized: "No")))
        }
        if !colourRows.isEmpty { atlas.sections.append(Section(title: "Colour", rows: colourRows)) }

        let gps = properties[kCGImagePropertyGPSDictionary] as? [CFString: Any] ?? [:]
        atlas.coordinate = coordinate(from: gps)
        atlas.heading = gps[kCGImagePropertyGPSImgDirection] as? Double

        var buckets: [String: [Row]] = [:]
        var seen = Set<String>()
        for (dictionaryKey, prefix) in dictionaries {
            guard let dictionary = properties[dictionaryKey] as? [CFString: Any] else { continue }
            for (rawKey, rawValue) in dictionary {
                let key = rawKey as String
                let lower = key.lowercased()
                guard !ignoredKeys.contains(lower) else { continue }
                guard !lower.contains("makernote"), !lower.contains("serial") else { continue }
                guard !(rawValue is Data) else { continue }
                let value = prettyValue(key: lower, raw: rawValue)
                guard !value.isEmpty else { continue }
                let label = prettyLabel(key)
                guard seen.insert(label).inserted else { continue }
                buckets[section(for: lower, prefix: prefix), default: []].append(Row(label: label, value: value))
            }
        }
        for row in xmpRows(source: source, data: data) where seen.insert(row.label).inserted {
            buckets["XMP", default: []].append(row)
        }
        atlas.fieldCount = seen.count

        for title in sectionOrder {
            guard let rows = buckets[title], !rows.isEmpty else { continue }
            atlas.sections.append(Section(title: title, rows: rows.sorted { (leading($0), $0.label) < (leading($1), $1.label) }))
        }
        return atlas
    }

    /// The atlas as plain text: a heading per section, a `label: value` line per row.
    public static func reportText(_ atlas: Atlas) -> String {
        var lines: [String] = []
        for section in atlas.sections {
            lines.append(section.localizedTitle.uppercased())
            for row in section.rows {
                lines.append("\(row.label): \(row.value)")
            }
            lines.append("")
        }
        if let coordinate = atlas.coordinate {
            lines.append(String(format: "GPS: %.6f, %.6f", coordinate.latitude, coordinate.longitude))
        }
        return lines.joined(separator: "\n")
    }

    // web parity: camera first
    private static let leadingLabels = ["Make", "Model", "Lens Make", "Lens Model"]

    private static func leading(_ row: Row) -> Int {
        leadingLabels.firstIndex(of: row.label) ?? leadingLabels.count
    }

    // cfstring constants are immutable
    nonisolated(unsafe) private static let dictionaries: [(CFString, String)] = [
        (kCGImagePropertyTIFFDictionary, "tiff"),
        (kCGImagePropertyExifDictionary, "exif"),
        (kCGImagePropertyExifAuxDictionary, "exif"),
        (kCGImagePropertyGPSDictionary, "gps"),
        (kCGImagePropertyIPTCDictionary, "iptc"),
        (kCGImagePropertyPNGDictionary, "png"),
        (kCGImagePropertyJFIFDictionary, "jfif"),
    ]

    private static let sectionOrder = ["Camera", "Capture", "Image", "Location", "Dates", "IPTC", "XMP", "Other"]

    // imageio synthesises these
    private static let mirroredPrefixes: Set<String> = ["exif", "exifEX", "tiff", "aux", "iio"]

    private static func xmpRows(source: CGImageSource, data: Data) -> [Row] {
        // no packet, all synthesised
        guard data.range(of: Data("<x:xmpmeta".utf8)) != nil || data.range(of: Data("<rdf:RDF".utf8)) != nil,
              let metadata = CGImageSourceCopyMetadataAtIndex(source, 0, nil),
              let tags = CGImageMetadataCopyTags(metadata) as? [CGImageMetadataTag]
        else { return [] }

        return tags.compactMap { tag in
            guard let prefix = CGImageMetadataTagCopyPrefix(tag) as String?,
                  !mirroredPrefixes.contains(prefix),
                  let name = CGImageMetadataTagCopyName(tag) as String?,
                  let value = xmpText(tag), !value.isEmpty
            else { return nil }
            return Row(label: prettyLabel(name), value: value)
        }
    }

    private static func xmpText(_ tag: CGImageMetadataTag) -> String? {
        switch CGImageMetadataTagCopyValue(tag) {
        case let text as String:
            return text
        case let items as [CGImageMetadataTag]:
            return items.compactMap(xmpText).joined(separator: ", ")
        default:
            return nil
        }
    }

    private static func section(for key: String, prefix: String) -> String {
        if prefix == "gps" { return "Location" }
        if prefix == "iptc" { return "IPTC" }
        if key.range(of: "make|model|lens|camera|software|artist|hostcomputer|copyright|owner",
                     options: .regularExpression) != nil { return "Camera" }
        if key.range(of: "fnumber|exposure|iso|shutter|focal|flash|whitebalance|metering|brightness|lightsource|aperture",
                     options: .regularExpression) != nil { return "Capture" }
        if key.range(of: "datetime|createdate|modifydate|offsettime|subsec",
                     options: .regularExpression) != nil { return "Dates" }
        if key.range(of: "width|height|dimension|orientation|resolution|colorspace|bitspersample|photometric|compress",
                     options: .regularExpression) != nil { return "Image" }
        return "Other"
    }

    private static let ignoredKeys: Set<String> = [
        "componentsconfiguration", "cfapattern", "oecf", "spatialfrequencyresponse",
        "devicesettingdescription", "printim", "interopindex", "interoperabilityindex",
        "exifversion", "flashpixversion", "gpsversionid", "gpsprocessingmethod",
        "gpsareainformation", "subjectarea", "subjectlocation", "whitepoint",
        "primarychromaticities", "ycbcrcoefficients", "referenceblackwhite",
        "stripoffsets", "stripbytecounts", "tileoffsets", "tilebytecounts", "rowsperstrip",
        "thumbnail", "padding", "offsetschema", "relatedsoundfile", "usercomment",
    ]

    private static let acronyms = [
        "Iso": "ISO", "Gps": "GPS", "Exif": "Exif", "Xmp": "XMP", "Iptc": "IPTC",
        "F Number": "F-Number", "Y Cb Cr": "YCbCr", "Dpi": "DPI", "S Rgb": "sRGB",
    ]

    private static let labelOverrides = [
        "Date Time Original": "Date Taken",
        "Focal Len In35mm Film": "35mm Equivalent",
        "Pixel X Dimension": "Pixel Width",
        "Pixel Y Dimension": "Pixel Height",
    ]

    /// An ImageIO key as a label: words split, acronyms kept, some renamed (`DateTimeOriginal` is Date Taken).
    public static func prettyLabel(_ key: String) -> String {
        var text = key.replacingOccurrences(of: "_", with: " ")
        text = text.replacingOccurrences(of: "([a-z0-9])([A-Z])", with: "$1 $2", options: .regularExpression)
        text = text.replacingOccurrences(of: "([A-Z])([A-Z][a-z])", with: "$1 $2", options: .regularExpression)
        text = text.split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }
            .joined(separator: " ")
        for (word, acronym) in acronyms {
            text = text.replacingOccurrences(of: "\\b\(word)\\b", with: acronym, options: .regularExpression)
        }
        return labelOverrides[text] ?? text
    }

    private static let enumLabels: [String: [Int: String]] = [
        "colorspace": [1: "sRGB", 65535: "Uncalibrated"],
        "ycbcrpositioning": [1: "Centered", 2: "Co-sited"],
        "contrast": [0: "Normal", 1: "Soft", 2: "Hard"],
        "saturation": [0: "Normal", 1: "Low", 2: "High"],
        "sharpness": [0: "Normal", 1: "Soft", 2: "Hard"],
        "customrendered": [0: "Normal", 1: "Custom"],
        "exposuremode": [0: "Auto", 1: "Manual", 2: "Auto bracket"],
        "whitebalance": [0: "Auto", 1: "Manual"],
        "scenecapturetype": [0: "Standard", 1: "Landscape", 2: "Portrait", 3: "Night scene"],
        "gaincontrol": [0: "None", 1: "Low gain up", 2: "High gain up"],
        "sensingmethod": [1: "Not defined", 2: "One-chip color area", 3: "Two-chip color area"],
        "filesource": [3: "Digital camera"],
        "scenetype": [1: "Directly photographed"],
        "subjectdistancerange": [0: "Unknown", 1: "Macro", 2: "Close view", 3: "Distant view"],
        "exposureprogram": [
            0: "Not defined", 1: "Manual", 2: "Normal program", 3: "Aperture priority",
            4: "Shutter priority", 5: "Creative program", 6: "Action program",
            7: "Portrait mode", 8: "Landscape mode",
        ],
        "meteringmode": [
            0: "Unknown", 1: "Average", 2: "Center-weighted average", 3: "Spot",
            4: "Multi-spot", 5: "Multi-segment", 6: "Partial", 255: "Other",
        ],
        "lightsource": [
            0: "Unknown", 1: "Daylight", 2: "Fluorescent", 3: "Tungsten (incandescent)",
            4: "Flash", 9: "Fine weather", 10: "Cloudy weather", 11: "Shade",
            12: "Daylight fluorescent", 13: "Day white fluorescent", 14: "Cool white fluorescent",
            15: "White fluorescent", 16: "Warm white fluorescent", 17: "Standard light A",
            18: "Standard light B", 19: "Standard light C", 20: "D55", 21: "D65",
            22: "D75", 23: "D50", 24: "ISO studio tungsten", 255: "Other",
        ],
        "resolutionunit": [2: "Inches", 3: "cm"],
        "gpsmeasuremode": [2: "2D measurement", 3: "3D measurement"],
        "orientation": [
            1: "Normal", 2: "Mirrored", 3: "Rotated 180°", 4: "Mirrored, 180°",
            5: "Mirrored, 270°", 6: "Rotated 90°", 7: "Mirrored, 90°", 8: "Rotated 270°",
        ],
    ]

    // exif infinity sentinel
    static let infinityThreshold = 4_294_967_245.0

    /// A metadata value as text, with units and EXIF enumerations named; `key` is lowercased.
    public static func prettyValue(key: String, raw: Any) -> String {
        let base = formatValue(raw)

        if let map = enumLabels[key], let number = raw as? Int, let mapped = map[number] {
            return mapped
        }

        if let number = raw as? Double {
            switch key {
            case "subjectdistance":
                return number >= infinityThreshold ? "Infinity" : "\(base) m"
            case "exposuretime":
                guard number >= 1e-6, number < 1 else { return base }
                return "\(base) (1/\(Int((1 / number).rounded()))s)"
            case "exposurebiasvalue", "exposurecompensation":
                return "\(base) EV"
            case "fnumber", "aperturevalue":
                return base.hasPrefix("f/") ? base : "f/\(base)"
            case "focallength", "focallenin35mmfilm", "focallengthin35mmformat":
                return "\(base) mm"
            case "altitude":
                return "\(base) m"
            case "imgdirection", "destbearing", "track":
                return "\(base)°"
            case "digitalzoomratio":
                return number == 0 ? "No zoom" : "\(base)×"
            default:
                break
            }
        }

        if key == "iso" || key == "isospeedratings" {
            return "ISO \(base)"
        }
        return base
    }

    private static func formatValue(_ value: Any) -> String {
        switch value {
        case let text as String:
            return text
        case let date as Date:
            return date.formatted(date: .abbreviated, time: .shortened)
        case let number as Double:
            // Int() traps on inf
            guard number.isFinite, abs(number) < 1e15 else { return String(format: "%g", number) }
            return number == number.rounded()
                ? String(Int(number))
                : String(format: "%g", (number * 1e6).rounded() / 1e6)
        case let number as Int:
            return String(number)
        case let flag as Bool:
            return flag ? String(localized: "Yes") : String(localized: "No")
        case let list as [Any]:
            return list.map(formatValue).joined(separator: ", ")
        default:
            return String(describing: value)
        }
    }

    private static func coordinate(from gps: [CFString: Any]) -> (Double, Double)? {
        guard var latitude = gps[kCGImagePropertyGPSLatitude] as? Double,
              var longitude = gps[kCGImagePropertyGPSLongitude] as? Double
        else { return nil }
        if (gps[kCGImagePropertyGPSLatitudeRef] as? String) == "S" { latitude = -latitude }
        if (gps[kCGImagePropertyGPSLongitudeRef] as? String) == "W" { longitude = -longitude }
        return (latitude, longitude)
    }
}
