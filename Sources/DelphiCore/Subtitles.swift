import Foundation

public struct SubtitleCue: Equatable, Hashable, Sendable {
    /// milliseconds
    public var start: Int
    /// milliseconds
    public var end: Int
    public var text: String

    public init(start: Int, end: Int, text: String) {
        (self.start, self.end, self.text) = (start, end, text)
    }
}

public enum SubtitleFormat: String, CaseIterable, Identifiable, Sendable {
    case srt, vtt

    public var id: String { rawValue }
    public var label: String { rawValue.uppercased() }
}

/// A recognised word; times in seconds.
public struct SubtitleWord: Equatable, Sendable {
    public var text: String
    public var start: Double
    public var end: Double

    public init(text: String, start: Double, end: Double) {
        (self.text, self.start, self.end) = (text, start, end)
    }
}

public enum SubtitleCodec: Sendable {

    // js trim strips u+feff
    private static let blank = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "\u{FEFF}"))

    private static func trim(_ value: some StringProtocol) -> String {
        String(value).trimmingCharacters(in: blank)
    }

    private static func digits(_ value: Substring, max: Int) -> Int? {
        guard (1...max).contains(value.count),
              value.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        return Int(value)
    }

    /// `[h+:]m{1,2}:s{1,2}[.,]f{1,3}`
    public static func parseTimestamp(_ value: String) -> Int? {
        let parts = trim(value).split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2 || parts.count == 3 else { return nil }
        let tail = parts[parts.count - 1].split(omittingEmptySubsequences: false) { $0 == "." || $0 == "," }
        guard tail.count == 2,
              let minutes = digits(parts[parts.count - 2], max: 2),
              let seconds = digits(tail[0], max: 2),
              digits(tail[1], max: 3) != nil,
              let millis = Int(tail[1].padding(toLength: 3, withPad: "0", startingAt: 0))
        else { return nil }
        var hours = 0
        if parts.count == 3 {
            guard let h = digits(parts[0], max: 9) else { return nil }
            hours = h
        }
        return hours * 3_600_000 + minutes * 60_000 + seconds * 1000 + millis
    }

    public static func formatTimestamp(_ ms: Int, separator: Character) -> String {
        let t = max(0, ms)
        return String(format: "%02d:%02d:%02d%@%03d",
                      t / 3_600_000, (t / 60_000) % 60, (t / 1000) % 60, String(separator), t % 1000)
    }

    public static func detectFormat(_ text: String) -> SubtitleFormat? {
        if trim(text).hasPrefix("WEBVTT") { return .vtt }
        return text.contains("-->") ? .srt : nil
    }

    /// Blocks without a timing line (index, WEBVTT header, NOTE, STYLE) are skipped.
    public static func parse(_ text: String) -> [SubtitleCue] {
        let normalised = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        var cues: [SubtitleCue] = []

        for block in normalised.components(separatedBy: "\n\n") {
            let lines = block.components(separatedBy: "\n")
            guard let timingIndex = lines.firstIndex(where: { $0.contains("-->") }) else { continue }

            let sides = lines[timingIndex].components(separatedBy: "-->")
            // settings follow end time
            let endRaw = trim(sides[1]).split(whereSeparator: \.isWhitespace).first.map(String.init) ?? ""
            guard let start = parseTimestamp(sides[0]), let end = parseTimestamp(endRaw) else { continue }

            let body = trim(lines[(timingIndex + 1)...].joined(separator: "\n"))
            cues.append(SubtitleCue(start: start, end: end, text: body))
        }
        return cues
    }

    public static func writeSRT(_ cues: [SubtitleCue]) -> String {
        cues.enumerated().map { index, cue in
            "\(index + 1)\n\(formatTimestamp(cue.start, separator: ",")) --> \(formatTimestamp(cue.end, separator: ","))\n\(cue.text)"
        }.joined(separator: "\n\n") + "\n"
    }

    public static func writeVTT(_ cues: [SubtitleCue], kind: String = "", language: String = "") -> String {
        var header = "WEBVTT"
        let kind = trim(kind), language = trim(language)
        if !kind.isEmpty { header += "\nKind: \(kind)" }
        if !language.isEmpty { header += "\nLanguage: \(language)" }
        return header + "\n\n" + cues.map { cue in
            "\(formatTimestamp(cue.start, separator: ".")) --> \(formatTimestamp(cue.end, separator: "."))\n\(cue.text)"
        }.joined(separator: "\n\n") + "\n"
    }

    public static func write(_ cues: [SubtitleCue], as format: SubtitleFormat, kind: String = "", language: String = "") -> String {
        format == .srt ? writeSRT(cues) : writeVTT(cues, kind: kind, language: language)
    }

    // int(_:) traps out-of-range
    private static let limitMs = 3.6e12

    private static func bounded(_ ms: Double) -> Int {
        ms.isNaN ? 0 : Int(min(max(ms, -limitMs), limitMs).rounded())
    }

    public static func shift(_ cues: [SubtitleCue], byMs delta: Int) -> [SubtitleCue] {
        cues.map { cue in
            let start = max(0, cue.start + delta)
            return SubtitleCue(start: start, end: max(start, cue.end + delta), text: cue.text)
        }
    }

    public static func scale(_ cues: [SubtitleCue], by factor: Double) -> [SubtitleCue] {
        cues.map { cue in
            SubtitleCue(start: bounded(Double(cue.start) * factor), end: bounded(Double(cue.end) * factor), text: cue.text)
        }
    }

    /// Scale before shift, as the web tool does.
    public static func retime(_ cues: [SubtitleCue], shiftSeconds: Double, scale factor: Double) -> [SubtitleCue] {
        var out = cues
        if factor != 1, factor > 0, factor.isFinite { out = scale(out, by: factor) }
        if shiftSeconds != 0, shiftSeconds.isFinite { out = shift(out, byMs: bounded(shiftSeconds * 1000)) }
        return out
    }

    public static func stripTags(_ text: String) -> String {
        text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
    }

    /// End exclusive.
    public static func activeIndex(in cues: [SubtitleCue], atMs ms: Double) -> Int? {
        cues.firstIndex { ms >= Double($0.start) && ms < Double($0.end) }
    }

    private static let maxChars = 42
    private static let maxDurationMs = 6000.0
    private static let gapBreakSeconds = 0.8

    private static func endsSentence(_ word: String) -> Bool {
        word.range(of: "[.!?…][\"')\\]]?$", options: .regularExpression) != nil
    }

    public static func cues(from words: [SubtitleWord]) -> [SubtitleCue] {
        var cues: [SubtitleCue] = []
        var buffer: [SubtitleWord] = []

        func flush() {
            guard let first = buffer.first, let last = buffer.last else { return }
            let start = max(0, bounded(first.start * 1000))
            cues.append(SubtitleCue(start: start, end: max(start, bounded(last.end * 1000)),
                                    text: buffer.map(\.text).joined(separator: " ")))
            buffer = []
        }

        for word in words {
            if let first = buffer.first, let last = buffer.last {
                let gap = word.start - last.end
                let wouldLength = buffer.reduce(0) { $0 + $1.text.utf16.count + 1 } + word.text.utf16.count
                let wouldDuration = word.end * 1000 - first.start * 1000
                if gap > gapBreakSeconds || wouldLength > maxChars || wouldDuration > maxDurationMs { flush() }
            }
            buffer.append(word)
            if endsSentence(word.text) { flush() }
        }
        flush()
        return cues
    }
}

#if DEBUG
extension SubtitleCodec {
    public static func selfCheck() {
        let srt = "1\n00:00:01,000 --> 00:00:02,500\nFirst line\n\n2\n00:00:03,000 --> 00:00:04,000\nSecond cue\nwith two lines\n"
        let vtt = "WEBVTT\n\nNOTE a comment block\n\nintro\n00:01.000 --> 00:02.500 position:10%,line-left align:center\nFirst line\n\n00:00:03.000 --> 00:00:04.000\nSecond cue\n"
        let first = SubtitleCue(start: 1000, end: 2500, text: "First line")

        assert(parseTimestamp("00:00:01,000") == 1000)
        assert(parseTimestamp("01:02:03.004") == 3_723_004)
        assert(parseTimestamp("02:03.004") == 123_004)
        assert(parseTimestamp("00:00:01.5") == 1500)
        assert(parseTimestamp("nonsense") == nil)
        assert(parseTimestamp("99999999999999999:00:00.000") == nil)
        assert(formatTimestamp(3_723_004, separator: ".") == "01:02:03.004")
        assert(formatTimestamp(-5, separator: ",") == "00:00:00,000")

        assert(detectFormat(vtt) == .vtt)
        assert(detectFormat("\u{FEFF}WEBVTT\n") == .vtt)
        assert(detectFormat(srt) == .srt)
        assert(detectFormat("plain text") == nil)

        let parsed = parse(srt)
        assert(parsed == [first, SubtitleCue(start: 3000, end: 4000, text: "Second cue\nwith two lines")])
        assert(parse("\u{FEFF}" + srt.replacingOccurrences(of: "\n", with: "\r\n")) == parsed)
        assert(parse(vtt) == [first, SubtitleCue(start: 3000, end: 4000, text: "Second cue")])
        assert(parse("00:00:01,000 --> 00:00:02,500\nFirst line") == [first])

        assert(writeSRT(parse(vtt)) == "1\n00:00:01,000 --> 00:00:02,500\nFirst line\n\n2\n00:00:03,000 --> 00:00:04,000\nSecond cue\n")
        let headed = writeVTT(parsed, kind: "captions", language: "en-GB")
        assert(headed.hasPrefix("WEBVTT\nKind: captions\nLanguage: en-GB\n\n"))
        assert(parse(headed) == parsed)
        assert(writeVTT(parsed, kind: "  ").hasPrefix("WEBVTT\n\n"))

        let one = [SubtitleCue(start: 500, end: 1500, text: "a")]
        assert(shift(one, byMs: -1000) == [SubtitleCue(start: 0, end: 500, text: "a")])
        assert(shift(one, byMs: -2000) == [SubtitleCue(start: 0, end: 0, text: "a")])
        assert(scale(one, by: 1.5) == [SubtitleCue(start: 750, end: 2250, text: "a")])
        assert(retime(one, shiftSeconds: -1e300, scale: 1e300) == [SubtitleCue(start: 0, end: 0, text: "a")])
        assert(cues(from: [SubtitleWord(text: "a", start: .nan, end: .infinity)]).count == 1)

        assert(stripTags("<i>Hi</i> <c.loud>there</c>") == "Hi there")
        assert(activeIndex(in: parsed, atMs: 2500) == nil)
        assert(activeIndex(in: parsed, atMs: 3000) == 1)

        assert(cues(from: []).isEmpty)
        let sentence = cues(from: [SubtitleWord(text: "Hello", start: 0, end: 0.4), SubtitleWord(text: "there.", start: 0.5, end: 0.9)])
        assert(sentence == [SubtitleCue(start: 0, end: 900, text: "Hello there.")])
        let gapped = cues(from: [SubtitleWord(text: "one", start: 0, end: 0.3), SubtitleWord(text: "two", start: 2, end: 2.3)])
        assert(gapped.count == 2)
        let long = cues(from: (0..<20).map { SubtitleWord(text: "wordy", start: Double($0) * 0.2, end: Double($0) * 0.2 + 0.1) })
        assert(long.count > 1 && long.allSatisfy { $0.text.count <= 42 })
    }
}
#endif
