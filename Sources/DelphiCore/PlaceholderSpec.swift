import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// What the Placeholder Generator writes: the web tool's placeholder, a filled rectangle with its label centred in bold
/// monospace.
public struct PlaceholderSpec: Equatable, Sendable {
    public static let sizes = 1...4096

    public var width: Int
    public var height: Int
    /// `#rrggbb`
    public var background: String
    public var foreground: String
    public var text: String

    public init(width: Int, height: Int, background: String, foreground: String, text: String) {
        (self.width, self.height, self.background, self.foreground, self.text) = (width, height, background, foreground, text)
    }

    public var label: String { text.isEmpty ? "\(width) × \(height)" : text }
    public var fontSize: Double { Double(min(width, height)) / 8 }
    public var baseName: String { "placeholder-\(width)x\(height)" }

    public var svg: String {
        let label = Self.escapeXML(label)
        return """
        <svg xmlns="http://www.w3.org/2000/svg" width="\(width)" height="\(height)" viewBox="0 0 \(width) \(height)">
          <rect fill="\(background)" width="\(width)" height="\(height)"/>
          <text fill="\(foreground)" font-family="monospace" font-size="\(Self.number(fontSize))" font-weight="bold" x="50%" y="50%" text-anchor="middle" dominant-baseline="middle">\(label)</text>
        </svg>
        """
    }

    /// - Parameter font: the bold monospaced face at `fontSize`.
    public func png(font: CTFont) -> Data? {
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { return nil }
        let size = CGSize(width: width, height: height)
        context.setFillColor(Self.colour(background))
        context.fill(CGRect(origin: .zero, size: size))
        let attributes = [kCTFontAttributeName: font, kCTForegroundColorAttributeName: Self.colour(foreground)] as CFDictionary
        let line = CTLineCreateWithAttributedString(CFAttributedStringCreate(nil, label as CFString, attributes))
        var (ascent, descent, leading): (CGFloat, CGFloat, CGFloat) = (0, 0, 0)
        let measured = CTLineGetTypographicBounds(line, &ascent, &descent, &leading)
        let top = (size.height - (ascent + descent + leading)) / 2
        context.textPosition = CGPoint(x: (size.width - measured) / 2, y: size.height - top - ascent)
        CTLineDraw(line, context)
        guard let image = context.makeImage() else { return nil }
        let out = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(out, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? out as Data : nil
    }

    public func dataURI(svg: String) -> String {
        "data:image/svg+xml;base64,\(Data(svg.utf8).base64EncodedString())"
    }

    public static func dataURI(png data: Data) -> String {
        "data:image/png;base64,\(data.base64EncodedString())"
    }

    public static func escapeXML(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }

    /// Whole numbers without a point, others to two places.
    public static func number(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.2f", value)
    }

    /// Width to height in lowest terms, or to two decimals against 1 when the terms stay large.
    public static func aspect(_ width: Int, _ height: Int) -> String {
        guard width > 0, height > 0 else { return "—" }
        func gcd(_ a: Int, _ b: Int) -> Int { b == 0 ? a : gcd(b, a % b) }
        let divisor = gcd(width, height)
        let (w, h) = (width / divisor, height / divisor)
        return max(w, h) <= 64 ? "\(w):\(h)" : String(format: "%.2f:1", Double(width) / Double(height))
    }

    /// sRGB, black for anything unreadable.
    public static func colour(_ hex: String) -> CGColor {
        let value = UInt32(hex.filter(\.isHexDigit).prefix(6), radix: 16) ?? 0
        let parts = [value >> 16 & 0xFF, value >> 8 & 0xFF, value & 0xFF].map { CGFloat($0) / 255 }
        return CGColor(colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!, components: parts + [1])!
    }

    #if DEBUG
    public static func selfCheck() {
        var spec = PlaceholderSpec(width: 800, height: 600, background: "#e2e2e2", foreground: "#666666", text: "")
        assert(spec.label == "800 × 600" && spec.fontSize == 75)
        assert(spec.svg.contains("font-size=\"75\"") && spec.svg.contains(">800 × 600</text>"))
        spec.text = "a<b & \"c\""
        assert(spec.svg.contains(">a&lt;b &amp; &quot;c&quot;</text>"))
        assert(aspect(1920, 1080) == "16:9" && aspect(1200, 630) == "40:21" && aspect(4096, 4095) == "1.00:1")
        assert(colour("#1e6626").components?.map { Int(($0 * 255).rounded()) } == [30, 102, 38, 255])
        assert(number(12.5) == "12.50" && number(125) == "125")
        let small = PlaceholderSpec(width: 40, height: 20, background: "#ff0000", foreground: "#ffffff", text: "")
        let png = small.png(font: CTFontCreateWithName("Menlo-Bold" as CFString, CGFloat(small.fontSize), nil))
        let decoded = png.flatMap { CGImageSourceCreateWithData($0 as CFData, nil) }.flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) }
        assert(decoded?.width == 40 && decoded?.height == 20)
    }
    #endif
}
