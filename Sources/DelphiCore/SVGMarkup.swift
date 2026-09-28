import CoreGraphics
import Foundation

/// Reading SVG markup without an XML parser: its size, and an outline of it for display.
public enum SVGMarkup {
    public static let valueLimit = 48
    public static let lineLimit = 240

    /// Whether `text` starts, after whitespace, as SVG or XML markup does.
    public static func looksLikeSVG(_ text: String) -> Bool {
        let head = text.drop { $0.isWhitespace }.prefix(5)
        return head.hasPrefix("<svg") || head.hasPrefix("<?xml") || head.hasPrefix("<!")
    }

    /// The root element's size in user units: the viewBox, else numeric width and height.
    public static func size(of svg: String) -> CGSize? {
        guard let open = svg.range(of: "<svg") else { return nil }
        let tag = svg[open.lowerBound...].prefix { $0 != ">" }
        if let box = attribute("viewBox", in: tag) {
            let numbers = box.split { $0 == " " || $0 == "," }.compactMap { Double($0) }
            if numbers.count == 4, numbers[2] > 0, numbers[3] > 0 { return CGSize(width: numbers[2], height: numbers[3]) }
        }
        func length(_ name: String) -> Double? {
            attribute(name, in: tag).flatMap { Double($0.hasSuffix("px") ? String($0.dropLast(2)) : $0) }
        }
        guard let width = length("width"), let height = length("height"), width > 0, height > 0 else { return nil }
        return CGSize(width: width, height: height)
    }

    /// A quoted attribute's value in a tag, found by ` name="` so `width` does not match `stroke-width`.
    public static func attribute(_ name: String, in tag: Substring) -> String? {
        for quote in ["\"", "'"] {
            guard let start = tag.range(of: " \(name)=\(quote)") ?? tag.range(of: "\n\(name)=\(quote)"),
                  let end = tag[start.upperBound...].firstIndex(of: Character(quote)) else { continue }
            return String(tag[start.upperBound..<end])
        }
        return nil
    }

    /// `svg` with a viewBox from its width and height when it has none, so it scales to its frame.
    public static func sizedForScaling(_ svg: String) -> String {
        guard let open = svg.range(of: "<svg"), attribute("viewBox", in: svg[open.lowerBound...].prefix { $0 != ">" }) == nil,
              let size = size(of: svg) else { return svg }
        var sized = svg
        sized.insert(contentsOf: " viewBox=\"0 0 \(size.width) \(size.height)\"", at: open.upperBound)
        return sized
    }

    /// The SVG as a data URL in an `<img>` that fills the page and contains the drawing, under a policy that loads
    /// nothing else, so the markup runs no script and reaches no network. `filter` is CSS for the image.
    public static func imagePage(_ svg: String, background: String, filter: String? = nil) -> String {
        let data = Data(sizedForScaling(svg).utf8).base64EncodedString()
        return """
        <!DOCTYPE html><html><head><meta name="viewport" content="width=device-width,initial-scale=1">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src data:; style-src 'unsafe-inline'">
        <style>html,body{margin:0;width:100%;height:100%;overflow:hidden;background:\(background)}
        img{display:block;width:100%;height:100%;object-fit:contain\(filter.map { ";filter:\($0)" } ?? "")}</style></head>
        <body><img alt="" src="data:image/svg+xml;base64,\(data)"></body></html>
        """
    }

    /// The markup indented, a line per tag or text run, long attribute values cut, at most `lineLimit` lines.
    public static func outline(_ svg: String) -> String {
        let bytes = Array(svg.utf8)
        var lines: [String] = []
        var hidden = 0
        var depth = 0
        var index = 0

        func emit(_ text: String, at level: Int) {
            guard lines.count < lineLimit else { return hidden += 1 }
            lines.append(String(repeating: "  ", count: max(level, 0)) + text)
        }
        func find(_ marker: String, from start: Int) -> Int {
            let target = Array(marker.utf8)
            var at = start
            while at + target.count <= bytes.count {
                if bytes[at] == target[0], Array(bytes[at..<at + target.count]) == target { return at + target.count }
                at += 1
            }
            return bytes.count
        }
        func starts(_ marker: String, at start: Int) -> Bool {
            let target = Array(marker.utf8)
            return start + target.count <= bytes.count && Array(bytes[start..<start + target.count]) == target
        }

        while index < bytes.count {
            guard bytes[index] == UInt8(ascii: "<") else {
                var end = index
                while end < bytes.count, bytes[end] != UInt8(ascii: "<") { end += 1 }
                let text = String(decoding: bytes[index..<end], as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty { emit(cut(text.replacingOccurrences(of: "\n", with: " ")), at: depth) }
                index = end
                continue
            }
            var end: Int
            if starts("<!--", at: index) {
                end = find("-->", from: index + 4)
            } else if starts("<![CDATA[", at: index) {
                end = find("]]>", from: index + 9)
            } else {
                end = index + 1
                var quote: UInt8?
                while end < bytes.count {
                    let byte = bytes[end]
                    if let open = quote {
                        if byte == open { quote = nil }
                    } else if byte == UInt8(ascii: "\"") || byte == UInt8(ascii: "'") {
                        quote = byte
                    } else if byte == UInt8(ascii: ">") {
                        break
                    }
                    end += 1
                }
                end = min(end + 1, bytes.count)
            }
            let tag = String(decoding: bytes[index..<end], as: UTF8.self)
            let isClosing = starts("</", at: index)
            let isLeaf = starts("<!", at: index) || starts("<?", at: index) || tag.hasSuffix("/>")
            if isClosing { depth -= 1 }
            emit(shortened(tag), at: depth)
            if !isClosing, !isLeaf { depth += 1 }
            index = end
        }
        if hidden > 0 { lines.append("<!-- \(String(localized: "\(hidden) more")) -->") }
        return lines.joined(separator: "\n")
    }

    private static func shortened(_ tag: String) -> String {
        var result = ""
        var rest = Substring(tag.replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "\t", with: " "))
        while let open = rest.firstIndex(where: { $0 == "\"" || $0 == "'" }) {
            let quote = rest[open]
            result += rest[...open]
            let valueStart = rest.index(after: open)
            guard let close = rest[valueStart...].firstIndex(of: quote) else {
                rest = rest[valueStart...]
                break
            }
            result += cut(String(rest[valueStart..<close])) + String(quote)
            rest = rest[rest.index(after: close)...]
        }
        return result + String(rest)
    }

    private static func cut(_ text: String) -> String {
        text.count > valueLimit ? String(text.prefix(valueLimit - 8)) + "…" : text
    }
}
