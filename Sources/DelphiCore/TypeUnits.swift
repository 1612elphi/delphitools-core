import Foundation

/// Units of type: px to rem, line height ratios, and the typesetter's units on one pixel scale.
public enum TypeUnits {
    /// Decimal pads type a comma in many locales.
    public static func parse(_ text: String) -> Double? {
        Double(text.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces))
    }

    private static let posix = Locale(identifier: "en_US_POSIX")

    /// At most four decimals, trailing zeros dropped: 0.5, 0.6875, 26.25.
    public static func format(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...4)).grouping(.never).locale(posix))
    }

    public static let commonPx: [Double] = [8, 10, 11, 12, 13, 14, 15, 16, 18, 20, 24, 28, 32, 36, 40, 48, 56, 64, 72, 80, 96]
    public static let commonFontSizes: [Double] = [10, 11, 12, 13, 14, 16, 18, 20, 24, 28, 32, 36, 40, 48, 56, 64, 72]

    public enum Ratio: String, CaseIterable, Sendable {
        case tight = "Tight"
        case normal = "Normal"
        case relaxed = "Relaxed"
        case loose = "Loose"
        case custom = "Custom"

        /// Custom's own value is the caller's.
        public var multiplier: Double {
            switch self {
            case .tight: 1.2
            case .normal, .custom: 1.5
            case .relaxed: 1.75
            case .loose: 2
            }
        }

        /// The preset `multiplier` matches, else custom.
        public static func matching(_ multiplier: Double) -> Ratio {
            allCases.first { $0 != .custom && abs($0.multiplier - multiplier) < 0.0005 } ?? .custom
        }
    }

    public enum Unit: String, CaseIterable, Sendable {
        case px, pt, pc, ag, cc, `in`, mm, cm, em, rem

        public var symbol: String { rawValue }

        public var name: String {
            switch self {
            case .px: String(localized: "Pixels")
            case .pt: String(localized: "Points")
            case .pc: String(localized: "Picas")
            case .ag: String(localized: "Agates")
            case .cc: String(localized: "Ciceros")
            case .in: String(localized: "Inches")
            case .mm: String(localized: "Millimetres")
            case .cm: String(localized: "Centimetres")
            case .em: "Em"
            case .rem: "Rem"
            }
        }

        /// - Parameter ppi: pixels per inch; CSS fixes it at 96.
        public func toPx(_ value: Double, base: Double, ppi: Double = 96) -> Double {
            switch self {
            case .px: value
            case .pt: value * (ppi / 72)
            case .pc: value * 12 * (ppi / 72)
            case .ag: value * (ppi / 14)
            // didot cicero, 4.512 mm
            case .cc: value * 4.512 * (ppi / 25.4)
            case .in: value * ppi
            case .mm: value * (ppi / 25.4)
            case .cm: value * (ppi / 2.54)
            case .em, .rem: value * base
            }
        }

        public func fromPx(_ px: Double, base: Double, ppi: Double = 96) -> Double {
            px / toPx(1, base: base, ppi: ppi)
        }

        /// A step a typesetter would take in the unit.
        public var step: Double {
            switch self {
            case .px, .pt, .ag, .mm: 1
            case .pc, .cc: 0.5
            case .in, .em, .rem: 0.125
            case .cm: 0.1
            }
        }
    }

    #if DEBUG
    public static func selfCheck() {
        assert(format(0.5) == "0.5" && format(1) == "1" && format(0.6875) == "0.6875")
        assert(parse("1,5") == 1.5 && parse("x") == nil)
        assert(format(26.25) == "26.25" && format(1.0 / 3) == "0.3333" && format(1234.5) == "1234.5")
        assert(Ratio.matching(1.75) == .relaxed && Ratio.matching(1.6) == .custom)
        assert(Unit.pt.toPx(72, base: 16) == 96 && Unit.pc.fromPx(16, base: 16) == 1)
        assert(abs(Unit.in.fromPx(Unit.mm.toPx(25.4, base: 16, ppi: 300), base: 16, ppi: 300) - 1) < 1e-12)
        assert(Unit.rem.fromPx(24, base: 16) == 1.5)
    }
    #endif
}

/// Counts of a text: words, characters, sentences, paragraphs, lines, and its most frequent words.
public struct WordCount: Sendable {
    public let text: String
    public let words: Int
    public let charactersNoSpaces: Int

    public init(_ text: String) {
        self.text = text
        words = text.split(whereSeparator: \.isWhitespace).count
        charactersNoSpaces = text.filter { !$0.isWhitespace }.count
    }

    public var characters: Int { text.count }

    public var sentences: Int {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return 0 }
        var count = 0
        text.enumerateSubstrings(in: text.startIndex..., options: [.bySentences, .substringNotRequired]) { _, _, _, _ in count += 1 }
        return count
    }

    public var paragraphs: Int {
        text.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count
    }

    public var lines: Int { text.isEmpty ? 0 : text.components(separatedBy: "\n").count }

    /// brysbaert 2019: 238 wpm
    public var readingMinutes: Double { Double(words) / 238 }
    public var speakingMinutes: Double { Double(words) / 150 }

    public var averageWordLength: Double { words == 0 ? 0 : Double(charactersNoSpaces) / Double(words) }

    /// Case-insensitive, three characters or more; ties alphabetical.
    public func topWords(limit: Int) -> [(word: String, count: Int)] {
        var frequency: [String: Int] = [:]
        for word in text.lowercased().components(separatedBy: .whitespacesAndNewlines) {
            let trimmed = word.trimmingCharacters(in: .punctuationCharacters)
            if trimmed.count >= 3 { frequency[trimmed, default: 0] += 1 }
        }
        return frequency.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .prefix(limit).map { (word: $0.key, count: $0.value) }
    }

    /// Localised; under a minute shows seconds only.
    public static func duration(_ minutes: Double) -> String {
        let seconds = Int((minutes * 60).rounded())
        let units: Set<Duration.UnitsFormatStyle.Unit> = seconds >= 60 ? [.minutes, .seconds] : [.seconds]
        return Duration.seconds(seconds).formatted(.units(allowed: units, width: .abbreviated))
    }

    #if DEBUG
    public static func selfCheck() {
        let count = WordCount("The cat sat. The cat ran!\nA dog.")
        assert(count.words == 8 && count.sentences == 3 && count.paragraphs == 2 && count.lines == 2)
        assert(count.topWords(limit: 2).map(\.word) == ["cat", "the"] && count.topWords(limit: 1)[0].count == 2)
        assert(WordCount("").paragraphs == 0 && WordCount("").sentences == 0 && WordCount("").averageWordLength == 0)
        assert(WordCount("ab cd").charactersNoSpaces == 4)
    }
    #endif
}
