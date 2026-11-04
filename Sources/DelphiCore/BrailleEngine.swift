import Foundation

/// Unified English Braille, grade 1.
public enum BrailleEngine {

    private static let blank: UInt32 = 0x2800

    private static func cell(_ dots: String) -> String {
        var mask: UInt32 = 0
        for dot in dots {
            guard let number = dot.wholeNumberValue else { continue }
            mask |= 1 << (number - 1)
        }
        return String(UnicodeScalar(blank + mask) ?? " ")
    }

    private static let letters = Array("abcdefghijklmnopqrstuvwxyz")
    private static let digits = Array("1234567890")

    private static let cells: [String] = (
        "1 12 14 145 15 124 1245 125 24 245 13 123 134 1345 135 1234 12345 " +
        "1235 234 2345 136 1236 2456 1346 13456 1356"
    ).split(separator: " ").map { cell(String($0)) }

    private static let letterOf: [String: Character] = {
        var map: [String: Character] = [:]
        for (index, pattern) in cells.enumerated() { map[pattern] = letters[index] }
        return map
    }()

    private static let punctuation: [(Character, String)] = [
        (",", "2"), (";", "23"), (":", "25"), (".", "256"), ("!", "235"),
        ("?", "236"), ("'", "3"), ("-", "36"),
        ("(", "5 126"), (")", "5 345"), ("/", "456 34"),
    ]

    private static let punctCells: [Character: String] = {
        var map: [Character: String] = [:]
        for (char, dots) in punctuation {
            map[char] = dots.split(separator: " ").map { cell(String($0)) }.joined()
        }
        return map
    }()

    private static let punctOf: [String: Character] = {
        var map: [String: Character] = [:]
        for (char, pattern) in punctCells { map[pattern] = char }
        return map
    }()

    private static let capital = cell("6")
    private static let number = cell("3456")
    private static let grade1 = cell("56")
    // UEB §7.6
    private static let openQuote = cell("236")
    private static let closeQuote = cell("356")

    private static func atWordStart(_ out: String) -> Bool {
        out.isEmpty || (out.last?.isWhitespace ?? false)
    }

    public static func toBraille(_ text: String) -> String {
        var out = ""
        var numeric = false
        for token in tokenise(text) {
            guard let first = token.first else { continue }
            if first.isNumber && first.isASCII {
                if !numeric { out += number }
                numeric = true
                for digit in token {
                    if let index = digits.firstIndex(of: digit) { out += cells[index] }
                }
                continue
            }
            if first.isLetter && first.isASCII {
                // UEB §6.5.1
                if numeric, let lead = token.lowercased().first, "abcdefghij".contains(lead) {
                    out += grade1
                }
                numeric = false
                let capsWord = token.count > 1 && token == token.uppercased()
                if capsWord { out += capital + capital }
                for char in token {
                    let lower = Character(char.lowercased())
                    if !capsWord && char != lower { out += capital }
                    if let index = letters.firstIndex(of: lower) { out += cells[index] }
                }
                continue
            }
            // UEB §6.2
            numeric = numeric && (token == "." || token == ",")
            if token == "\"" {
                out += atWordStart(out) ? openQuote : closeQuote
            } else if let pattern = punctCells[first], token.count == 1 {
                out += pattern
            } else {
                out += token
            }
        }
        return out
    }

    // letter runs, digit runs, singles
    private static func tokenise(_ text: String) -> [String] {
        var out: [String] = []
        var current = ""
        var kind: Int = 0 // 1 letters, 2 digits
        for char in text {
            let next = char.isASCII && char.isLetter ? 1 : (char.isASCII && char.isNumber ? 2 : 0)
            if next != 0 && next == kind {
                current.append(char)
                continue
            }
            if !current.isEmpty { out.append(current) }
            current = String(char)
            kind = next
            if next == 0 {
                out.append(current)
                current = ""
            }
        }
        if !current.isEmpty { out.append(current) }
        return out
    }

    /// One step of reading braille: the cells taken and the text they give. An indicator gives no text.
    public struct Reading: Equatable {
        public enum Kind { case letter, indicator, other }
        public let cells: String
        public let text: String
        public let kind: Kind
    }

    public static func fromBraille(_ cellString: String) -> String {
        read(cellString).map(\.text).joined()
    }

    public static func read(_ cellString: String) -> [Reading] {
        let chars = cellString.map(String.init)
        var readings: [Reading] = []
        var out = ""
        var numeric = false
        var capsWord = false
        var capsNext = false
        var i = 0
        func emit(_ count: Int, _ text: String, _ kind: Reading.Kind) {
            readings.append(Reading(cells: chars[i..<i + count].joined(), text: text, kind: kind))
            out += text
            i += count
        }
        while i < chars.count {
            let c = chars[i]
            if c == capital {
                if i + 1 < chars.count && chars[i + 1] == capital {
                    capsWord = true
                    emit(2, "", .indicator)
                } else {
                    capsNext = true
                    emit(1, "", .indicator)
                }
                continue
            }
            if c == number {
                numeric = true
                emit(1, "", .indicator)
                continue
            }
            if c == grade1 {
                numeric = false
                emit(1, "", .indicator)
                continue
            }
            if let letter = letterOf[c] {
                let index = letters.firstIndex(of: letter) ?? 0
                if numeric && index < 10 {
                    emit(1, String(digits[index]), .letter)
                    continue
                }
                numeric = false
                let text = capsNext || capsWord ? letter.uppercased() : String(letter)
                capsNext = false
                emit(1, text, .letter)
                continue
            }
            capsWord = false
            let pair = punctOf[c + (i + 1 < chars.count ? chars[i + 1] : "")]
            if let pair {
                numeric = false
                // last cell: one-cell key
                emit(min(2, chars.count - i), String(pair), .letter)
                continue
            }
            if c == openQuote {
                numeric = false
                emit(1, atWordStart(out) ? "\"" : "?", .letter)
                continue
            }
            if c == closeQuote {
                numeric = false
                emit(1, "\"", .letter)
                continue
            }
            let punct = punctOf[c].map(String.init)
            let text = punct ?? c
            numeric = numeric && (text == "." || text == ",")
            emit(1, text, punct == nil ? .other : .letter)
        }
        return readings
    }

    public static func looksLikeBraille(_ text: String) -> Bool {
        text.unicodeScalars.contains { (0x2800...0x28ff).contains($0.value) }
    }

    /// Dot numbers of one cell, e.g. "1-2-5", or empty for anything else.
    public static func dots(_ pattern: String) -> String {
        guard let scalar = pattern.unicodeScalars.first else { return "" }
        let mask = Int(scalar.value) - Int(blank)
        guard mask > 0, mask <= 0xff else { return "" }
        return (1...8).filter { mask & (1 << ($0 - 1)) != 0 }
            .map(String.init)
            .joined(separator: "-")
    }

    #if DEBUG
    public static func selfCheck() {
        assert(toBraille("a") == "\u{2801}")
        assert(fromBraille(toBraille("hello world")) == "hello world")
        assert(fromBraille(toBraille("Hello")) == "Hello")
        assert(fromBraille(toBraille("BBC")) == "BBC")
        assert(fromBraille(toBraille("123")) == "123")
        assert(fromBraille(toBraille("1a")) == "1a")
        assert(dots("\u{2801}") == "1")
        assert(looksLikeBraille("\u{2801}"))
        let readings = read(toBraille("Hi 1"))
        assert(readings.map(\.text) == ["", "H", "i", " ", "", "1"])
        assert(readings.first?.kind == .indicator && readings[3].kind == .other)
        assert(read(toBraille("(a)")).first?.cells.count == 2)
        assert(fromBraille(toBraille("end.")) == "end.")
        assert(!looksLikeBraille("abc"))
    }
    #endif
}
