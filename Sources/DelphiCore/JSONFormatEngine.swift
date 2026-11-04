import Foundation

public nonisolated struct JSONMember: Sendable {
    public let key: String
    public let value: JSONValue
}

/// Numbers keep their source text, so long integers and exponents survive a
/// round trip that `Double` would round off.
public nonisolated enum JSONValue: Sendable {
    case object([JSONMember])
    case array([JSONValue])
    case string(String)
    case number(String)
    case bool(Bool)
    case null
}

public nonisolated struct JSONParseError: Error, Equatable, Sendable {
    public let message: String
    public let line: Int
    /// 1-based, counted in characters.
    public let column: Int
    /// The error line, windowed to `excerptRadius` characters each side.
    public let excerpt: String
    /// Characters of `excerpt` before the error.
    public let caret: Int
}

public nonisolated enum JSONIndent: String, CaseIterable, Identifiable, Sendable {
    case two = "2"
    case four = "4"
    case tab
    case minify

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .two: String(localized: "2 spaces")
        case .four: String(localized: "4 spaces")
        case .tab: String(localized: "Tabs")
        case .minify: String(localized: "Minify")
        }
    }

    fileprivate var unit: String? {
        switch self {
        case .two: "  "
        case .four: "    "
        case .tab: "\t"
        case .minify: nil
        }
    }
}

public nonisolated struct JSONTreeRow: Identifiable, Sendable {
    /// Index path from the root; the collapse-state key.
    public let id: String
    public let key: String?
    public let depth: Int
    public let display: String
    public let isContainer: Bool
    public let isCollapsed: Bool
}

public nonisolated enum JSONFormatEngine {

    // 512 kb thread stacks
    public static let maxDepth = 128
    public static let excerptRadius = 24

    public static func parse(_ source: String) -> Result<JSONValue, JSONParseError> {
        var scanner = Scanner(bytes: Array(source.utf8))
        do {
            return .success(try scanner.parseDocument())
        } catch let error as JSONParseError {
            return .failure(error)
        } catch {
            return .failure(JSONParseError(message: String(localized: "Invalid JSON"), line: 1, column: 1,
                                           excerpt: "", caret: 0))
        }
    }

    private enum Byte {
        static let quote = UInt8(ascii: "\"")
        static let backslash = UInt8(ascii: "\\")
        static let newline = UInt8(ascii: "\n")
        static let minus = UInt8(ascii: "-")
        static let digits = UInt8(ascii: "0")...UInt8(ascii: "9")
    }

    private struct Scanner {
        let bytes: [UInt8]
        var index = 0
        var depth = 0

        private var current: UInt8? { index < bytes.count ? bytes[index] : nil }

        private func isCurrent(_ character: Unicode.Scalar) -> Bool {
            current == UInt8(ascii: character)
        }

        private func text(_ range: Range<Int>) -> String {
            String(decoding: bytes[range], as: UTF8.self)
        }

        private func fail(_ message: String, at position: Int? = nil) -> JSONParseError {
            let at = min(position ?? index, bytes.count)
            let lineStart = bytes[..<at].lastIndex(of: Byte.newline).map { $0 + 1 } ?? 0
            let line = bytes[..<lineStart].reduce(1) { $1 == Byte.newline ? $0 + 1 : $0 }
            let before = text(lineStart..<at)

            // cut on scalar boundary
            let reach = excerptRadius * 4
            var tail = min(at + reach, bytes.count)
            while tail < bytes.count, bytes[tail] & 0xC0 == 0x80 { tail += 1 }
            let after = text(at..<tail).prefix { !$0.isNewline }.prefix(excerptRadius)
            let lead = before.suffix(excerptRadius)

            return JSONParseError(message: message, line: line, column: before.count + 1,
                                  excerpt: String(lead + after), caret: lead.count)
        }

        private mutating func skipWhitespace() {
            while let c = current, c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D {
                index += 1
            }
        }

        mutating func parseDocument() throws -> JSONValue {
            let value = try parseValue()
            skipWhitespace()
            guard current == nil else { throw fail(String(localized: "Trailing content")) }
            return value
        }

        private mutating func parseValue() throws -> JSONValue {
            skipWhitespace()
            guard let c = current else { throw fail(String(localized: "Unexpected end")) }
            switch c {
            case UInt8(ascii: "{"), UInt8(ascii: "["):
                guard depth < maxDepth else { throw fail(String(localized: "Nesting too deep")) }
                depth += 1
                defer { depth -= 1 }
                return c == UInt8(ascii: "{") ? try parseObject() : try parseArray()
            case Byte.quote: return .string(try parseString())
            case UInt8(ascii: "t"): try expect("true"); return .bool(true)
            case UInt8(ascii: "f"): try expect("false"); return .bool(false)
            case UInt8(ascii: "n"): try expect("null"); return .null
            case Byte.minus, Byte.digits: return .number(try parseNumber())
            default: throw fail(String(localized: "Unexpected token"))
            }
        }

        private mutating func expect(_ word: String) throws {
            let start = index
            for expected in word.utf8 {
                guard current == expected else { throw fail(String(localized: "Unexpected token"), at: start) }
                index += 1
            }
        }

        private mutating func parseObject() throws -> JSONValue {
            index += 1
            var members: [JSONMember] = []
            skipWhitespace()
            if isCurrent("}") {
                index += 1
                return .object(members)
            }
            while true {
                skipWhitespace()
                guard current == Byte.quote else { throw fail(String(localized: "Expected key")) }
                let key = try parseString()
                skipWhitespace()
                guard isCurrent(":") else { throw fail(String(localized: "Expected colon")) }
                index += 1
                members.append(JSONMember(key: key, value: try parseValue()))
                skipWhitespace()
                if isCurrent(",") {
                    index += 1
                    continue
                }
                if isCurrent("}") {
                    index += 1
                    return .object(members)
                }
                throw current == nil ? fail(String(localized: "Unexpected end")) : fail(String(localized: "Expected comma"))
            }
        }

        private mutating func parseArray() throws -> JSONValue {
            index += 1
            var items: [JSONValue] = []
            skipWhitespace()
            if isCurrent("]") {
                index += 1
                return .array(items)
            }
            while true {
                items.append(try parseValue())
                skipWhitespace()
                if isCurrent(",") {
                    index += 1
                    continue
                }
                if isCurrent("]") {
                    index += 1
                    return .array(items)
                }
                throw current == nil ? fail(String(localized: "Unexpected end")) : fail(String(localized: "Expected comma"))
            }
        }

        private mutating func parseString() throws -> String {
            let start = index
            index += 1
            var unescaped: [UInt8] = []
            var runStart = index
            while true {
                guard let c = current else { throw fail(String(localized: "Unterminated string"), at: start) }
                switch c {
                case Byte.quote:
                    defer { index += 1 }
                    if unescaped.isEmpty { return text(runStart..<index) }
                    unescaped += bytes[runStart..<index]
                    return String(decoding: unescaped, as: UTF8.self)
                case Byte.backslash:
                    unescaped += bytes[runStart..<index]
                    index += 1
                    guard let escape = current else { throw fail(String(localized: "Unterminated string"), at: start) }
                    index += 1
                    switch escape {
                    case Byte.quote, Byte.backslash, UInt8(ascii: "/"): unescaped.append(escape)
                    case UInt8(ascii: "b"): unescaped.append(0x08)
                    case UInt8(ascii: "f"): unescaped.append(0x0C)
                    case UInt8(ascii: "n"): unescaped.append(0x0A)
                    case UInt8(ascii: "r"): unescaped.append(0x0D)
                    case UInt8(ascii: "t"): unescaped.append(0x09)
                    case UInt8(ascii: "u"):
                        UTF8.encode(try parseUnicodeEscape()) { unescaped.append($0) }
                    default: throw fail(String(localized: "Invalid escape"), at: index - 2)
                    }
                    runStart = index
                case 0..<0x20:
                    throw fail(String(localized: "Control character"))
                default:
                    index += 1
                }
            }
        }

        private mutating func parseUnicodeEscape() throws -> Unicode.Scalar {
            let escapeStart = index - 2
            var code = try readHex4()
            if (0xD800...0xDBFF).contains(code), current == Byte.backslash,
               index + 1 < bytes.count, bytes[index + 1] == UInt8(ascii: "u") {
                let mark = index
                index += 2
                let low = try readHex4()
                if (0xDC00...0xDFFF).contains(low) {
                    code = 0x10000 + ((code - 0xD800) << 10) + (low - 0xDC00)
                } else {
                    index = mark
                }
            }
            // no lone surrogates
            guard let scalar = Unicode.Scalar(code) else {
                throw fail(String(localized: "Invalid escape"), at: escapeStart)
            }
            return scalar
        }

        private mutating func readHex4() throws -> UInt32 {
            var value: UInt32 = 0
            for _ in 0..<4 {
                guard let c = current,
                      let digit = Character(Unicode.Scalar(c)).hexDigitValue else {
                    throw fail(String(localized: "Invalid escape"))
                }
                value = value * 16 + UInt32(digit)
                index += 1
            }
            return value
        }

        private mutating func skipDigits(numberStart: Int) throws {
            guard let c = current, Byte.digits.contains(c) else {
                throw fail(String(localized: "Invalid number"), at: numberStart)
            }
            while let c = current, Byte.digits.contains(c) { index += 1 }
        }

        private mutating func parseNumber() throws -> String {
            let start = index
            if current == Byte.minus { index += 1 }
            if isCurrent("0") {
                index += 1
            } else {
                try skipDigits(numberStart: start)
            }
            if isCurrent(".") {
                index += 1
                try skipDigits(numberStart: start)
            }
            if isCurrent("e") || isCurrent("E") {
                index += 1
                if isCurrent("+") || current == Byte.minus { index += 1 }
                try skipDigits(numberStart: start)
            }
            return text(start..<index)
        }
    }

    public static func format(_ value: JSONValue, indent: JSONIndent) -> String {
        var out = ""
        write(value, unit: indent.unit, depth: 0, into: &out)
        return out
    }

    private static func write(_ value: JSONValue, unit: String?, depth: Int, into out: inout String) {
        switch value {
        case .null: out += "null"
        case .bool(let flag): out += flag ? "true" : "false"
        case .number(let literal): out += literal
        case .string(let text): out += escaped(text)
        case .array(let items):
            writeContainer("[", "]", count: items.count, unit: unit, depth: depth, into: &out) {
                write(items[$0], unit: unit, depth: depth + 1, into: &$1)
            }
        case .object(let members):
            writeContainer("{", "}", count: members.count, unit: unit, depth: depth, into: &out) {
                $1 += escaped(members[$0].key) + (unit == nil ? ":" : ": ")
                write(members[$0].value, unit: unit, depth: depth + 1, into: &$1)
            }
        }
    }

    private static func writeContainer(_ open: String, _ close: String, count: Int,
                                       unit: String?, depth: Int, into out: inout String,
                                       entry: (Int, inout String) -> Void) {
        guard count > 0 else {
            out += open + close
            return
        }
        let pad = unit.map { "\n" + String(repeating: $0, count: depth + 1) } ?? ""
        out += open
        for index in 0..<count {
            out += pad
            entry(index, &out)
            if index < count - 1 { out += "," }
        }
        out += (unit.map { "\n" + String(repeating: $0, count: depth) } ?? "") + close
    }

    public static func escaped(_ text: String) -> String {
        guard text.utf8.contains(where: { $0 < 0x20 || $0 == 0x22 || $0 == 0x5C }) else {
            return "\"\(text)\""
        }
        var out = "\""
        for scalar in text.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            case "\u{8}": out += "\\b"
            case "\u{C}": out += "\\f"
            default:
                if scalar.value < 0x20 {
                    out += String(format: "\\u%04x", scalar.value)
                } else {
                    out.unicodeScalars.append(scalar)
                }
            }
        }
        return out + "\""
    }

    public static func rows(_ root: JSONValue, collapsed: Set<String>) -> [JSONTreeRow] {
        var rows: [JSONTreeRow] = []

        func container(_ summary: String, _ key: String?, _ path: String, _ depth: Int,
                       _ children: [(key: String, value: JSONValue)]) {
            let isCollapsed = collapsed.contains(path)
            rows.append(JSONTreeRow(id: path, key: key, depth: depth, display: summary,
                                    isContainer: true, isCollapsed: isCollapsed))
            guard !isCollapsed else { return }
            for (index, child) in children.enumerated() {
                walk(child.value, child.key, "\(path).\(index)", depth + 1)
            }
        }

        func walk(_ value: JSONValue, _ key: String?, _ path: String, _ depth: Int) {
            let display: String
            switch value {
            case .array(let items):
                return container("[\(items.count)]", key, path, depth,
                                 items.enumerated().map { (String($0), $1) })
            case .object(let members):
                return container("{\(members.count)}", key, path, depth,
                                 members.map { ($0.key, $0.value) })
            case .null: display = "null"
            case .bool(let flag): display = flag ? "true" : "false"
            case .number(let literal): display = literal
            case .string(let text): display = escaped(clipped(text))
            }
            rows.append(JSONTreeRow(id: path, key: key, depth: depth, display: display,
                                    isContainer: false, isCollapsed: false))
        }

        walk(root, nil, "root", 0)
        return rows
    }

    // ponytail: rows are one line; a full multi-megabyte string stalls text layout
    private static func clipped(_ text: String) -> String {
        let limit = 200
        guard text.utf8.count > limit * 8 else { return text }
        return String(text.prefix(limit)) + "…" + text.suffix(limit)
    }

    #if DEBUG
    public static func selfCheck() {
        guard case .success(let value) = parse(#"{"b":1,"a":[1,2],"big":12345678901234567890}"#)
        else { assertionFailure("valid JSON rejected"); return }
        assert(format(value, indent: .minify)
               == #"{"b":1,"a":[1,2],"big":12345678901234567890}"#)
        assert(format(value, indent: .two).hasPrefix("{\n  \"b\": 1,"))

        guard case .success(let nested) = parse(#"{"a":{},"b":[]}"#) else {
            assertionFailure("empty containers rejected"); return
        }
        assert(format(nested, indent: .two) == "{\n  \"a\": {},\n  \"b\": []\n}")

        guard case .success(let escapes) = parse(#""aé\n😀\ud83d\ude00\u00e9\/""#) else {
            assertionFailure("escapes rejected"); return
        }
        assert(format(escapes, indent: .minify) == #""aé\n😀😀é/""#)

        guard case .failure(let error) = parse("{\r\n  \"é😀\": x\r\n}") else {
            assertionFailure("invalid JSON accepted"); return
        }
        assert(error.line == 2 && error.column == 9)
        assert(error.excerpt == "  \"é😀\": x" && error.caret == 8)

        guard case .failure(let truncated) = parse("{\"a\":") else {
            assertionFailure("truncated JSON accepted"); return
        }
        assert(truncated.message == String(localized: "Unexpected end"))

        for invalid in ["[1,]", "[01]", "[1.]", "[-]", "[1e]", "[٣]", "[1] x", #""\ud83d""#,
                        #""\ude00""#, #""\x""#, "\"a\nb\"", "nul", ""] {
            if case .success = parse(invalid) { assertionFailure("accepted \(invalid)") }
        }
        for valid in ["-0.5e+10", " [ ] ", "\"\"", "[1E5,0,-0]"] {
            if case .failure = parse(valid) { assertionFailure("rejected \(valid)") }
        }

        let deep = { (depth: Int) in
            String(repeating: "[", count: depth) + String(repeating: "]", count: depth)
        }
        if case .failure = parse(deep(maxDepth)) { assertionFailure("depth limit too low") }
        guard case .failure(let tooDeep) = parse(deep(100_000)) else {
            assertionFailure("unbounded nesting accepted"); return
        }
        assert(tooDeep.message == String(localized: "Nesting too deep"))

        guard case .success(let twins) = parse(#"{"a":[1],"a":2}"#) else {
            assertionFailure("duplicate keys rejected"); return
        }
        let rows = rows(twins, collapsed: ["root.0"])
        assert(rows.count == 3)
        assert(rows[1].isCollapsed && rows[1].display == "[1]")
        assert(Set(rows.map(\.id)).count == 3)
    }
    #endif
}
