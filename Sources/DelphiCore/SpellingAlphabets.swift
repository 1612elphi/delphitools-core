import Foundation

public struct SpellingAlphabet: Identifiable, Hashable, Sendable {
    public let id: String
    public let label: String
    public let words: [String: String]
}

public enum SpellingAlphabets {

    private static let digitsDE = [
        "0": "Null", "1": "Eins", "2": "Zwei", "3": "Drei", "4": "Vier",
        "5": "Fünf", "6": "Sechs", "7": "Sieben", "8": "Acht", "9": "Neun",
    ]

    public static let all: [SpellingAlphabet] = [
        SpellingAlphabet(id: "nato", label: "NATO", words: [
            "A": "Alfa", "B": "Bravo", "C": "Charlie", "D": "Delta", "E": "Echo",
            "F": "Foxtrot", "G": "Golf", "H": "Hotel", "I": "India", "J": "Juliett",
            "K": "Kilo", "L": "Lima", "M": "Mike", "N": "November", "O": "Oscar",
            "P": "Papa", "Q": "Quebec", "R": "Romeo", "S": "Sierra", "T": "Tango",
            "U": "Uniform", "V": "Victor", "W": "Whiskey", "X": "X-ray",
            "Y": "Yankee", "Z": "Zulu",
            "0": "Zero", "1": "One", "2": "Two", "3": "Three", "4": "Four",
            "5": "Five", "6": "Six", "7": "Seven", "8": "Eight", "9": "Nine",
        ]),
        // DIN 5009:2022 city names
        SpellingAlphabet(id: "din5009", label: "DIN 5009", words: [
            "A": "Aachen", "B": "Berlin", "C": "Chemnitz", "D": "Düsseldorf",
            "E": "Essen", "F": "Frankfurt", "G": "Goslar", "H": "Hamburg",
            "I": "Ingelheim", "J": "Jena", "K": "Köln", "L": "Leipzig",
            "M": "München", "N": "Nürnberg", "O": "Offenbach", "P": "Potsdam",
            "Q": "Quickborn", "R": "Rostock", "S": "Salzwedel", "T": "Tübingen",
            "U": "Unna", "V": "Völklingen", "W": "Wuppertal", "X": "Xanten",
            "Y": "Ypsilon", "Z": "Zwickau",
            "Ä": "Umlaut Aachen", "Ö": "Umlaut Offenbach", "Ü": "Umlaut Unna",
            "ß": "Eszett",
        ].merging(digitsDE) { current, _ in current }),
        // DIN 5009:1996 words
        SpellingAlphabet(id: "german", label: String(localized: "German (1996)"), words: [
            "A": "Anton", "B": "Berta", "C": "Cäsar", "D": "Dora", "E": "Emil",
            "F": "Friedrich", "G": "Gustav", "H": "Heinrich", "I": "Ida",
            "J": "Julius", "K": "Kaufmann", "L": "Ludwig", "M": "Martha",
            "N": "Nordpol", "O": "Otto", "P": "Paula", "Q": "Quelle",
            "R": "Richard", "S": "Samuel", "T": "Theodor", "U": "Ulrich",
            "V": "Viktor", "W": "Wilhelm", "X": "Xanthippe", "Y": "Ypsilon",
            "Z": "Zacharias",
            "Ä": "Ärger", "Ö": "Ökonom", "Ü": "Übermut", "ß": "Eszett",
        ].merging(digitsDE) { current, _ in current }),
    ]

    public struct SpelledChar {
        public let char: Character
        public let word: String?
    }

    // ß uppercases to ss
    public static func spell(_ text: String, alphabet: SpellingAlphabet) -> [SpelledChar] {
        text.map { char in
            SpelledChar(char: char,
                        word: alphabet.words[String(char)] ?? alphabet.words[char.uppercased()])
        }
    }

    public static func spellText(_ text: String, alphabet: SpellingAlphabet) -> String {
        spell(text, alphabet: alphabet)
            .map { $0.word ?? ($0.char.isWhitespace ? "/" : String($0.char)) }
            .joined(separator: " ")
    }

    public static func unspell(_ words: String, alphabet: SpellingAlphabet) -> String {
        read(words, alphabet: alphabet).map(\.value).joined()
    }

    public static func looksSpelled(_ text: String, alphabet: SpellingAlphabet) -> Bool {
        let tokens = read(text, alphabet: alphabet)
        let count = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: \.isWhitespace).count
        return count >= 2 && tokens.allSatisfy(\.known)
    }

    private struct ReadToken {
        public let value: String
        public let known: Bool
    }

    private static func key(_ word: String) -> String {
        word.lowercased().replacingOccurrences(of: "-", with: "")
    }

    private static func reverse(_ alphabet: SpellingAlphabet) -> [String: String] {
        var map: [String: String] = ["/": " "]
        for (char, word) in alphabet.words { map[key(word)] = char }
        return map
    }

    private static func read(_ text: String, alphabet: SpellingAlphabet) -> [ReadToken] {
        let map = reverse(alphabet)
        let tokens = text.split(whereSeparator: \.isWhitespace).map(String.init)
        var out: [ReadToken] = []
        var i = 0
        while i < tokens.count {
            // two-word entries win first
            let next = i + 1 < tokens.count ? tokens[i + 1] : ""
            if let pair = map[key("\(tokens[i]) \(next)")] {
                out.append(ReadToken(value: pair, known: true))
                i += 2
                continue
            }
            let single = map[key(tokens[i])]
            out.append(ReadToken(value: single ?? tokens[i], known: single != nil))
            i += 1
        }
        return out
    }

    #if DEBUG
    public static func selfCheck() {
        let nato = all[0]
        assert(spellText("ab c", alphabet: nato) == "Alfa Bravo / Charlie")
        assert(unspell("Alfa Bravo / Charlie", alphabet: nato) == "AB C")
        assert(looksSpelled("Alfa Bravo", alphabet: nato))
        assert(!looksSpelled("Alfa", alphabet: nato))
        assert(!looksSpelled("hello there", alphabet: nato))
        assert(unspell("X-ray Yankee", alphabet: nato) == "XY")
        let din = all[1]
        assert(unspell("Umlaut Aachen Berlin", alphabet: din) == "ÄB")
    }
    #endif
}
