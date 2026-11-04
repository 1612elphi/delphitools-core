import Foundation

public nonisolated enum MorseEngine {

    // itu-r m.1677-1, plus !;&_$
    public static let table: [Character: String] = [
        "A": ".-", "B": "-...", "C": "-.-.", "D": "-..", "E": ".",
        "F": "..-.", "G": "--.", "H": "....", "I": "..", "J": ".---",
        "K": "-.-", "L": ".-..", "M": "--", "N": "-.", "O": "---",
        "P": ".--.", "Q": "--.-", "R": ".-.", "S": "...", "T": "-",
        "U": "..-", "V": "...-", "W": ".--", "X": "-..-", "Y": "-.--",
        "Z": "--..",
        "0": "-----", "1": ".----", "2": "..---", "3": "...--", "4": "....-",
        "5": ".....", "6": "-....", "7": "--...", "8": "---..", "9": "----.",
        ".": ".-.-.-", ",": "--..--", "?": "..--..", "'": ".----.",
        "!": "-.-.--", "/": "-..-.", "(": "-.--.", ")": "-.--.-",
        "&": ".-...", ":": "---...", ";": "-.-.-.", "=": "-...-",
        "+": ".-.-.", "-": "-....-", "_": "..--.-", "\"": ".-..-.",
        "$": "...-..-", "@": ".--.-.",
    ]

    public static let reverse: [String: Character] = {
        var map: [String: Character] = [:]
        for (char, code) in table { map[code] = char }
        return map
    }()

    public static func encode(_ text: String) -> String {
        text.uppercased()
            .split(whereSeparator: \.isWhitespace)
            .map { word in word.compactMap { table[$0] }.joined(separator: " ") }
            .filter { !$0.isEmpty }
            .joined(separator: " / ")
    }

    public static func decode(_ morse: String) -> String {
        words(morse)
            .map { word in String(word.map { reverse[$0] ?? "\u{fffd}" }) }
            .joined(separator: " ")
    }

    public static func looksLikeMorse(_ text: String) -> Bool {
        let stripped = text.filter { !$0.isWhitespace }
        guard !stripped.isEmpty else { return false }
        return stripped.allSatisfy { ".\u{b7}\u{2022}-\u{2013}\u{2014}_/".contains($0) }
    }

    public struct Timing {
        public let on: Bool
        public let ms: Double
    }

    // paris timing, 50 units
    public static func timings(_ morse: String, wpm: Int) -> [Timing] {
        let unit = 1200.0 / Double(wpm)
        var out: [Timing] = []
        for (w, word) in words(morse).enumerated() {
            if w > 0 { out.append(Timing(on: false, ms: 7 * unit)) }
            for (c, code) in word.enumerated() {
                if c > 0 { out.append(Timing(on: false, ms: 3 * unit)) }
                for (s, symbol) in code.enumerated() {
                    if s > 0 { out.append(Timing(on: false, ms: unit)) }
                    out.append(Timing(on: true, ms: (symbol == "-" ? 3 : 1) * unit))
                }
            }
        }
        return out
    }

    /// Words of codes. A slash or a run of `minimumGap` or more spaces ends a word.
    public static func words(_ morse: String, minimumGap: Int = 3) -> [[String]] {
        var marked = ""
        var run = 0
        for char in morse.trimmingCharacters(in: .whitespacesAndNewlines) {
            if char.isWhitespace {
                run += 1
                continue
            }
            if run > 0 { marked.append(run >= minimumGap ? "/" : " ") }
            run = 0
            switch char {
            case "\u{b7}", "\u{2022}": marked.append(".")
            case "\u{2013}", "\u{2014}", "_": marked.append("-")
            default: marked.append(char)
            }
        }
        return marked.split(separator: "/")
            .map { $0.split(separator: " ").map(String.init) }
            .filter { !$0.isEmpty }
    }

    #if DEBUG
    public static func selfCheck() {
        assert(encode("SOS") == "... --- ...")
        assert(encode("hello world") == ".... . .-.. .-.. --- / .-- --- .-. .-.. -..")
        assert(decode(".... . .-.. .-.. --- / .-- --- .-. .-.. -..") == "HELLO WORLD")
        assert(decode("...   ---   ...") == "S O S")
        assert(looksLikeMorse(".- -..."))
        assert(!looksLikeMorse("abc"))
        assert(!looksLikeMorse("   "))
        assert(decode("..--..") == "?")
        assert(timings(".", wpm: 20).count == 1)
        assert(timings("..", wpm: 20).map(\.on) == [true, false, true])
        assert(words("...  ---").count == 1)
        assert(words("...  ---", minimumGap: 2).count == 2)
    }
    #endif
}
