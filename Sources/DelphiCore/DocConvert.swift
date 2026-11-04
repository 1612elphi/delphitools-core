import CoreGraphics
import Foundation

/// Block model behind the Document Converter. Reads Markdown, HTML and plain
/// text; writes Markdown, HTML, plain text, RTF and PDF. The SDK ships no
/// reader for Markdown or HTML, so both readers here are hand-written.
public enum DocConvert {

    // MARK: - Formats

    public enum Format: String, CaseIterable, Identifiable, Sendable {
        case markdown, html, rtf, plain, pdf

        public var id: String { rawValue }

        public var label: String {
            switch self {
            case .markdown: "Markdown"
            case .html: "HTML"
            case .rtf: String(localized: "Rich Text")
            case .plain: String(localized: "Plain text")
            case .pdf: "PDF"
            }
        }

        public var ext: String {
            switch self {
            case .markdown: "md"
            case .html: "html"
            case .rtf: "rtf"
            case .plain: "txt"
            case .pdf: "pdf"
            }
        }

        public var readable: Bool {
            switch self {
            case .markdown, .html, .plain: true
            case .rtf, .pdf: false
            }
        }

        public static var inputs: [Format] { allCases.filter(\.readable) }
        public static var outputs: [Format] { allCases }
    }

    // MARK: - Model

    public struct Inline: Equatable, Sendable {
        public var text: String
        public var bold = false
        public var italic = false
        public var code = false
        public var link: String?

        public init(text: String, bold: Bool = false, italic: Bool = false, code: Bool = false, link: String? = nil) {
            (self.text, self.bold, self.italic, self.code, self.link) = (text, bold, italic, code, link)
        }
    }

    public enum Block: Equatable, Sendable {
        case heading(level: Int, runs: [Inline])
        case paragraph([Inline])
        case list(ordered: Bool, items: [[Inline]])
        case quote([Inline])
        case code(String)
        case rule
    }

    public struct Style: Equatable, Sendable {
        public enum Family: Int, Sendable { case sans, serif, mono }

        public struct RGB: Equatable, Sendable {
            public var red: CGFloat, green: CGFloat, blue: CGFloat
            public var css: String { String(format: "#%02x%02x%02x", Int(red * 255), Int(green * 255), Int(blue * 255)) }
            public init(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat) { (self.red, self.green, self.blue) = (red, green, blue) }
        }

        public var family: Family
        /// multiple of font's own
        public var lineHeight: CGFloat
        public var text: RGB
        public var background: RGB

        public init(family: Family, lineHeight: CGFloat, text: RGB, background: RGB) {
            (self.family, self.lineHeight, self.text, self.background) = (family, lineHeight, text, background)
        }

        public var cssFamily: String {
            switch family {
            case .sans: "-apple-system, system-ui, sans-serif"
            case .serif: "ui-serif, Georgia, serif"
            case .mono: "ui-monospace, Menlo, monospace"
            }
        }
    }

    public enum Output: Sendable {
        case text(String)
        case data(Data)
    }

    // MARK: - Entry points

    public static func parse(_ source: String, as format: Format) -> [Block] {
        switch format {
        case .markdown: parseMarkdown(source)
        case .html: parseHTML(source)
        case .plain, .rtf, .pdf: parsePlain(source)
        }
    }

    // MARK: - Detection

    public static func format(forFilename name: String) -> Format? {
        switch (name as NSString).pathExtension.lowercased() {
        case "md", "markdown", "mdown", "mkd": .markdown
        case "html", "htm", "xhtml": .html
        case "txt", "text": .plain
        default: nil
        }
    }

    /// Sniffed from the opening of the document only; the view calls this per
    /// keystroke and the whole string would be copied and scanned each time.
    public static func format(forContent source: String) -> Format {
        let text = source.prefix(4096).replacingOccurrences(of: "\u{FEFF}", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return .markdown }
        if text.firstMatch(of: /^<(\?xml|!doctype html|html|head|body|div|p|h[1-6]|article|section|table|ul|ol)[\s>\/]/.ignoresCase()) != nil {
            return .html
        }
        if text.firstMatch(of: /(?m)^(#{1,6}\s|[-*+]\s|>\s|```|\d+\.\s)/) != nil { return .markdown }
        return .plain
    }

    // MARK: - Markdown reader

    public static func parseMarkdown(_ source: String) -> [Block] {
        markdownBlocks(source).map(\.block)
    }

    public static func markdownBlocks(_ source: String) -> [(block: Block, lines: Range<Int>)] {
        var blocks: [(block: Block, lines: Range<Int>)] = []
        var paragraph: [String] = []
        var paragraphStart = 0
        let lines = source.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var index = 0

        func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            blocks.append((.paragraph(parseInline(paragraph.joined(separator: " "))), paragraphStart..<index))
            paragraph = []
        }

        while index < lines.count {
            let line = lines[index].trimmingCharacters(in: .whitespaces)

            if line.isEmpty {
                flushParagraph()
                index += 1
                continue
            }

            let start = index
            if line.hasPrefix("```") || line.hasPrefix("~~~") {
                flushParagraph()
                let fence = String(line.prefix(3))
                var body: [String] = []
                index += 1
                while index < lines.count,
                      !lines[index].trimmingCharacters(in: .whitespaces).hasPrefix(fence) {
                    body.append(lines[index])
                    index += 1
                }
                if index < lines.count { index += 1 }
                blocks.append((.code(body.joined(separator: "\n")), start..<index))
                continue
            }

            if let (level, rest) = headingParts(line) {
                flushParagraph()
                index += 1
                blocks.append((.heading(level: level, runs: parseInline(rest)), start..<index))
                continue
            }

            if !paragraph.isEmpty, let level = setextLevel(line) {
                let runs = parseInline(paragraph.joined(separator: " "))
                paragraph = []
                index += 1
                blocks.append((.heading(level: level, runs: runs), paragraphStart..<index))
                continue
            }

            if isRule(line) {
                flushParagraph()
                index += 1
                blocks.append((.rule, start..<index))
                continue
            }

            if line.hasPrefix(">") {
                flushParagraph()
                var body: [String] = []
                while index < lines.count {
                    let quoted = lines[index].trimmingCharacters(in: .whitespaces)
                    guard quoted.hasPrefix(">") else { break }
                    body.append(String(quoted.dropFirst()).trimmingCharacters(in: .whitespaces))
                    index += 1
                }
                blocks.append((.quote(parseInline(body.joined(separator: " "))), start..<index))
                continue
            }

            if bulletBody(line) != nil || orderedBody(line) != nil {
                let ordered = bulletBody(line) == nil
                flushParagraph()
                var items: [[Inline]] = []
                while index < lines.count {
                    let item = lines[index].trimmingCharacters(in: .whitespaces)
                    guard let body = ordered ? orderedBody(item) : bulletBody(item) else { break }
                    items.append(parseInline(body))
                    index += 1
                }
                blocks.append((.list(ordered: ordered, items: items), start..<index))
                continue
            }

            if paragraph.isEmpty { paragraphStart = index }
            paragraph.append(line)
            index += 1
        }

        flushParagraph()
        return blocks
    }

    private static func headingParts(_ line: String) -> (Int, String)? {
        let hashes = line.prefix { $0 == "#" }.count
        guard (1...6).contains(hashes) else { return nil }
        let rest = String(line.dropFirst(hashes))
        guard rest.hasPrefix(" ") || rest.isEmpty else { return nil }
        let body = rest.trimmingCharacters(in: .whitespaces)
        return (hashes, String(body.reversed().drop { $0 == "#" }.reversed()).trimmingCharacters(in: .whitespaces))
    }

    // commonmark setext underline
    private static func setextLevel(_ line: String) -> Int? {
        guard line.count >= 2, let first = line.first, first == "=" || first == "-",
              line.allSatisfy({ $0 == first }) else { return nil }
        return first == "=" ? 1 : 2
    }

    private static func isRule(_ line: String) -> Bool {
        let squeezed = line.replacingOccurrences(of: " ", with: "")
        guard squeezed.count >= 3, let first = squeezed.first, "-*_".contains(first) else { return false }
        return squeezed.allSatisfy { $0 == first }
    }

    private static func bulletBody(_ line: String) -> String? {
        for marker in ["- ", "* ", "+ "] where line.hasPrefix(marker) {
            return String(line.dropFirst(marker.count))
        }
        return nil
    }

    private static func orderedBody(_ line: String) -> String? {
        let digits = line.prefix { $0.isNumber }
        guard !digits.isEmpty else { return nil }
        let rest = line.dropFirst(digits.count)
        guard let separator = rest.first, separator == "." || separator == ")",
              rest.dropFirst().hasPrefix(" ") else { return nil }
        return String(rest.dropFirst(2))
    }

    public static func parseInline(_ source: String) -> [Inline] {
        var runs: [Inline] = []
        var buffer = ""
        let chars = Array(source)
        var index = 0

        func flush() {
            guard !buffer.isEmpty else { return }
            runs.append(Inline(text: buffer))
            buffer = ""
        }

        func find(_ needle: Character, from start: Int) -> Int? {
            var cursor = start
            while cursor < chars.count {
                if chars[cursor] == needle { return cursor }
                cursor += 1
            }
            return nil
        }

        func findMarker(_ marker: [Character], from start: Int) -> Int? {
            var cursor = start
            while cursor + marker.count <= chars.count {
                if Array(chars[cursor..<(cursor + marker.count)]) == marker { return cursor }
                cursor += 1
            }
            return nil
        }

        // a forward-only cursor: `[` with no `]` after it would otherwise
        // rescan the rest of the paragraph for every bracket
        var bracketCursor = 0
        func findCloseBracket(from start: Int) -> Int? {
            bracketCursor = max(bracketCursor, start)
            while bracketCursor < chars.count, chars[bracketCursor] != "]" { bracketCursor += 1 }
            return bracketCursor < chars.count ? bracketCursor : nil
        }

        while index < chars.count {
            let character = chars[index]

            if character == "\\", index + 1 < chars.count {
                buffer.append(chars[index + 1])
                index += 2
                continue
            }

            if character == "`", let end = find("`", from: index + 1), end > index + 1 {
                flush()
                runs.append(Inline(text: String(chars[(index + 1)..<end]), code: true))
                index = end + 1
                continue
            }

            if character == "*" || character == "_" {
                let doubled = index + 1 < chars.count && chars[index + 1] == character
                let marker = Array(repeating: character, count: doubled ? 2 : 1)
                // commonmark: no intraword emphasis
                let wordBoundary = character == "*" || index == 0 || !chars[index - 1].isLetter
                if wordBoundary, let end = findMarker(marker, from: index + marker.count), end > index + marker.count,
                   character == "*" || end + marker.count >= chars.count || !chars[end + marker.count].isLetter {
                    let inner = String(chars[(index + marker.count)..<end])
                    flush()
                    runs.append(contentsOf: parseInline(inner).map { run in
                        var marked = run
                        if doubled { marked.bold = true } else { marked.italic = true }
                        return marked
                    })
                    index = end + marker.count
                    continue
                }
            }

            if character == "[", let close = findCloseBracket(from: index + 1),
               close + 1 < chars.count, chars[close + 1] == "(",
               let paren = find(")", from: close + 2) {
                let label = String(chars[(index + 1)..<close])
                let url = String(chars[(close + 2)..<paren])
                flush()
                runs.append(contentsOf: parseInline(label).map { run in
                    var linked = run
                    linked.link = url
                    return linked
                })
                index = paren + 1
                continue
            }

            buffer.append(character)
            index += 1
        }

        flush()
        return runs
    }

    // MARK: - Plain text reader

    public static func parsePlain(_ source: String) -> [Block] {
        source.replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { .paragraph([Inline(text: $0.replacingOccurrences(of: "\n", with: " "))]) }
    }

    // MARK: - HTML reader

    public static func parseHTML(_ source: String) -> [Block] {
        let cleaned = source
            .replacing(/(?is)<!--.*?-->/, with: "")
            .replacing(/(?is)<script\b[^>]*>.*?<\/script>/, with: "")
            .replacing(/(?is)<style\b[^>]*>.*?<\/style>/, with: "")
            .replacing(/(?is)<head\b[^>]*>.*?<\/head>/, with: "")

        var blocks: [Block] = []
        var runs: [Inline] = []
        var text = ""
        var bold = 0, italic = 0, code = 0
        var link: String?
        var pending: String?
        var pendingLevel = 1
        var listItems: [[Inline]] = []
        var listOrdered = false
        var inList = false

        func flushText() {
            guard !text.isEmpty else { return }
            runs.append(Inline(text: text, bold: bold > 0, italic: italic > 0,
                               code: code > 0, link: link))
            text = ""
        }

        func closeBlock() {
            flushText()
            let content = runs
            runs = []
            defer { pending = nil }
            let empty = content.allSatisfy { $0.text.trimmingCharacters(in: .whitespaces).isEmpty }
            guard let pending else {
                if !empty { blocks.append(.paragraph(content)) }
                return
            }
            switch pending {
            case "li":
                if !empty { listItems.append(content) }
            case "pre":
                if !empty { blocks.append(.code(content.map(\.text).joined())) }
            case "blockquote":
                if !empty { blocks.append(.quote(content)) }
            case "h":
                if !empty { blocks.append(.heading(level: pendingLevel, runs: content)) }
            default:
                if !empty { blocks.append(.paragraph(content)) }
            }
        }

        func closeList() {
            closeBlock()
            if !listItems.isEmpty { blocks.append(.list(ordered: listOrdered, items: listItems)) }
            listItems = []
            inList = false
        }

        let characters = Array(cleaned)
        var index = 0
        while index < characters.count {
            if characters[index] != "<" {
                var raw = ""
                while index < characters.count, characters[index] != "<" {
                    raw.append(characters[index])
                    index += 1
                }
                let decoded = decodeEntities(raw)
                let collapsed = pending == "pre"
                    ? decoded
                    : decoded.replacing(/\s+/, with: " ")
                if collapsed.trimmingCharacters(in: .whitespaces).isEmpty {
                    // keeps inter-tag word gaps
                    if !runs.isEmpty || !text.isEmpty { text += " " }
                } else {
                    text += collapsed
                }
                continue
            }

            guard let close = characters[index...].firstIndex(of: ">") else { break }
            let tag = String(characters[(index + 1)..<close])
            index = close + 1

            let closing = tag.hasPrefix("/")
            let body = closing ? String(tag.dropFirst()) : tag
            let name = body.prefix { !$0.isWhitespace && $0 != "/" }.lowercased()

            switch name {
            case "p", "div", "blockquote", "pre", "li", "h1", "h2", "h3", "h4", "h5", "h6":
                if closing {
                    closeBlock()
                } else {
                    closeBlock()
                    if name.hasPrefix("h"), let level = Int(name.dropFirst()) {
                        pending = "h"
                        pendingLevel = level
                    } else {
                        pending = name == "div" ? "p" : name
                    }
                }
            case "ul", "ol":
                if closing {
                    closeList()
                } else {
                    if inList { closeList() }
                    closeBlock()
                    inList = true
                    listOrdered = name == "ol"
                    listItems = []
                }
            case "hr":
                guard !closing else { break }
                closeBlock()
                blocks.append(.rule)
            case "br":
                text += " "
            case "strong", "b":
                flushText()
                bold += closing ? -1 : 1
                bold = max(0, bold)
            case "em", "i":
                flushText()
                italic += closing ? -1 : 1
                italic = max(0, italic)
            case "code":
                flushText()
                code += closing ? -1 : 1
                code = max(0, code)
            case "a":
                flushText()
                if closing {
                    link = nil
                } else if let href = body.firstMatch(of: /href\s*=\s*["']([^"']*)["']/) {
                    link = String(href.1)
                }
            default:
                break
            }
        }

        // unconditional: `<li>` outside any list still has items to flush
        closeList()
        return blocks
    }

    private static func decodeEntities(_ source: String) -> String {
        guard source.contains("&") else { return source }
        var out = source
        for (entity, replacement) in [
            ("&nbsp;", "\u{00A0}"), ("&mdash;", "—"), ("&ndash;", "–"),
            ("&hellip;", "…"), ("&rsquo;", "’"), ("&lsquo;", "‘"),
            ("&ldquo;", "“"), ("&rdquo;", "”"), ("&quot;", "\""),
            ("&apos;", "'"), ("&#39;", "'"), ("&lt;", "<"), ("&gt;", ">"),
        ] {
            out = out.replacingOccurrences(of: entity, with: replacement)
        }
        out = out.replacing(/&#(\d+);/) { match in
            guard let code = UInt32(match.1), let scalar = Unicode.Scalar(code) else { return String(match.0) }
            return String(Character(scalar))
        }
        out = out.replacing(/&#[xX]([0-9a-fA-F]+);/) { match in
            guard let code = UInt32(match.1, radix: 16),
                  let scalar = Unicode.Scalar(code) else { return String(match.0) }
            return String(Character(scalar))
        }
        return out.replacingOccurrences(of: "&amp;", with: "&")
    }

    // MARK: - Writers

    public static func markdown(_ blocks: [Block]) -> String {
        let rendered = blocks.map { block -> String in
            switch block {
            case .heading(let level, let runs):
                String(repeating: "#", count: level) + " " + inlineMarkdown(runs)
            case .paragraph(let runs):
                inlineMarkdown(runs)
            case .quote(let runs):
                "> " + inlineMarkdown(runs)
            case .code(let body):
                "```\n" + body + "\n```"
            case .rule:
                "---"
            case .list(let ordered, let items):
                items.enumerated()
                    .map { (ordered ? "\($0.offset + 1). " : "- ") + inlineMarkdown($0.element) }
                    .joined(separator: "\n")
            }
        }
        return rendered.joined(separator: "\n\n") + (rendered.isEmpty ? "" : "\n")
    }

    private static func inlineMarkdown(_ runs: [Inline]) -> String {
        runs.map { run in
            var out = run.text
            if run.code { out = "`\(out)`" }
            if run.bold { out = "**\(out)**" }
            if run.italic { out = "*\(out)*" }
            if let link = run.link { out = "[\(out)](\(link))" }
            return out
        }.joined()
    }

    public static func html(_ blocks: [Block], standalone: Bool, style: Style? = nil) -> String {
        let body = blocks.map { block -> String in
            switch block {
            case .heading(let level, let runs):
                "<h\(level)>\(inlineHTML(runs))</h\(level)>"
            case .paragraph(let runs):
                "<p>\(inlineHTML(runs))</p>"
            case .quote(let runs):
                "<blockquote><p>\(inlineHTML(runs))</p></blockquote>"
            case .code(let source):
                "<pre><code>\(escapeHTML(source))</code></pre>"
            case .rule:
                "<hr>"
            case .list(let ordered, let items):
                (ordered ? "<ol>\n" : "<ul>\n")
                    + items.map { "<li>\(inlineHTML($0))</li>" }.joined(separator: "\n")
                    + (ordered ? "\n</ol>" : "\n</ul>")
            }
        }.joined(separator: "\n")

        guard standalone else { return body }
        return """
        <!DOCTYPE html>
        <html>
        <head><meta charset="utf-8"><title>Document</title>\(style.map(css) ?? "")</head>
        <body>
        \(body)
        </body>
        </html>
        """
    }

    private static func inlineHTML(_ runs: [Inline]) -> String {
        runs.map { run in
            var out = escapeHTML(run.text)
            if run.code { out = "<code>\(out)</code>" }
            if run.bold { out = "<strong>\(out)</strong>" }
            if run.italic { out = "<em>\(out)</em>" }
            if let link = run.link { out = "<a href=\"\(escapeHTML(link))\">\(out)</a>" }
            return out
        }.joined()
    }

    private static func escapeHTML(_ source: String) -> String {
        source
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    public static func plain(_ blocks: [Block]) -> String {
        let rendered = blocks.map { block -> String in
            switch block {
            case .heading(_, let runs), .paragraph(let runs), .quote(let runs):
                runs.map(\.text).joined()
            case .code(let body):
                body
            case .rule:
                "---"
            case .list(let ordered, let items):
                items.enumerated()
                    .map { (ordered ? "\($0.offset + 1). " : "• ") + $0.element.map(\.text).joined() }
                    .joined(separator: "\n")
            }
        }
        return rendered.joined(separator: "\n\n") + (rendered.isEmpty ? "" : "\n")
    }

    private static func css(_ style: Style) -> String {
        "<style>body { font-family: \(style.cssFamily); line-height: \(style.lineHeight); color: \(style.text.css); background: \(style.background.css); max-width: 40em; margin: 2em auto; padding: 0 1em; }</style>"
    }

    #if DEBUG
    public static func selfCheck() {
        let blocks = parseMarkdown("# Title\n\nSome **bold** and `code`.\n\n- one\n- two\n\n> quoted\n")
        assert(blocks.count == 4, "heading, paragraph, list, quote")
        guard case .heading(let level, let runs) = blocks[0] else { return assertionFailure("heading") }
        assert(level == 1 && runs.first?.text == "Title")
        guard case .list(let ordered, let items) = blocks[2] else { return assertionFailure("list") }
        assert(!ordered && items.count == 2)

        let inline = parseInline("a **b** [c](https://x) `d`")
        assert(inline.contains { $0.bold && $0.text == "b" })
        assert(inline.contains { $0.link == "https://x" && $0.text == "c" })
        assert(inline.contains { $0.code && $0.text == "d" })

        let fromHTML = parseHTML("<h2>Hi</h2><p>a <b>b</b></p><ul><li>x</li><li>y</li></ul>")
        assert(fromHTML.count == 3)
        guard case .heading(let htmlLevel, _) = fromHTML[0] else { return assertionFailure("h2") }
        assert(htmlLevel == 2)
        guard case .list(_, let htmlItems) = fromHTML[2] else { return assertionFailure("ul") }
        assert(htmlItems.count == 2)

        let stray = parseHTML("<LI>a</LI><li>b</li>")
        guard case .list(_, let strayItems) = stray.first else { return assertionFailure("stray li") }
        assert(strayItems.count == 2)
        assert(decodeEntities("&#x41;&#66;&#xZZ;") == "AB&#xZZ;")
        assert(parseInline(String(repeating: "[", count: 4000)).count == 1)

        assert(markdown(parseHTML(html(blocks, standalone: false))).contains("# Title"))
        assert(format(forContent: "<p>hi</p>") == .html)
        assert(format(forContent: "# hi") == .markdown)
        assert(format(forFilename: "notes.MD") == .markdown)
        assert(!plain(blocks).contains("**"))

        let look = Style(family: .serif, lineHeight: 1.6, text: .init(0, 0, 0), background: .init(1, 1, 0.5))
        assert(html(blocks, standalone: true, style: look).contains("line-height: 1.6") && !html(blocks, standalone: true).contains("<style>"))
        assert(look.background.css == "#ffff7f")

        let spans = markdownBlocks("# T\n\npara one\npara two\n\n- a\n- b\n\n```\nx\n```\nSet\n===")
        assert(spans.map(\.lines) == [0..<1, 2..<4, 5..<7, 8..<11, 11..<13], "block lines")
        assert(spans.map(\.block.mark) == ["H1", "\u{00B6}", "\u{2022}", "{ }", "H1"] && spans[1].block.words == 4)
    }
    #endif
}

extension DocConvert.Block {
    public var mark: String {
        switch self {
        case .heading(let level, _): "H\(level)"
        case .paragraph: "\u{00B6}"
        case .list(let ordered, _): ordered ? "1." : "\u{2022}"
        case .quote: "\u{201C}"
        case .code: "{ }"
        case .rule: "\u{2014}"
        }
    }

    public var text: String {
        switch self {
        case .heading(_, let runs), .paragraph(let runs), .quote(let runs): runs.map(\.text).joined()
        case .list(_, let items): items.map { $0.map(\.text).joined() }.joined(separator: " ")
        case .code(let body): body
        case .rule: ""
        }
    }

    public var words: Int {
        text.split(whereSeparator: \.isWhitespace).count
    }
}
