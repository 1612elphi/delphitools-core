import Foundation

/// English to IPA over the Shavian tool's ARPABET dictionaries, falling back to
/// its grapheme heuristic for words that are not listed.
public enum IPAEngine {

    public enum Token {
        case word(value: String, ipa: String, guess: Bool)
        case other(String)

        public var ipa: String {
            switch self {
            case .word(_, let ipa, _): ipa
            case .other(let value): value
            }
        }
    }

    private static let stress: [Character: String] = ["1": "\u{02c8}", "2": "\u{02cc}"]

    private static func isVowel(_ phone: String) -> Bool {
        phone.last?.isNumber ?? false
    }

    // ponytail: maximal onset — every consonant since the previous vowel goes
    // with the stressed syllable, so "abstain" gives əˈbsteɪn for əbˈsteɪn.
    // Sonority-sequencing syllabification is the upgrade.
    public static func wordToIpa(_ phones: [String]) -> String {
        let polysyllabic = phones.filter(isVowel).count > 1
        // cmu marks both compound halves
        let lastPrimary = phones.lastIndex { $0.hasSuffix("1") } ?? -1
        var out = ""
        var onset = ""
        for (index, phone) in phones.enumerated() {
            let ipa = ShavianPhonemeMap.ipaString(for: phone) ?? "?"
            guard isVowel(phone) else {
                onset += ipa
                continue
            }
            let mark: Character = phone.hasSuffix("1") && index != lastPrimary
                ? "2"
                : (phone.last ?? "0")
            out += (polysyllabic ? (stress[mark] ?? "") : "") + onset + ipa
            onset = ""
        }
        return out + onset
    }

    public static func transcribe(_ text: String, lookup: (String) -> [String]?) -> [Token] {
        tokenise(text).map { value in
            guard let first = value.first, (first.isASCII && first.isLetter) || first == "'" else {
                return .other(value)
            }
            if let phones = lookup(value.lowercased()) {
                return .word(value: value, ipa: wordToIpa(phones), guess: false)
            }
            let guessed = ShavianHeuristic.transliterate(value).map(\.ipa).joined()
            return .word(value: value, ipa: guessed, guess: true)
        }
    }

    public static func text(_ tokens: [Token]) -> String {
        tokens.map(\.ipa).joined()
    }

    // letter and apostrophe runs
    private static func tokenise(_ text: String) -> [String] {
        var out: [String] = []
        var current = ""
        var inWord: Bool?
        for char in text {
            let isWordChar = (char.isASCII && char.isLetter) || char == "'"
            if inWord != isWordChar, !current.isEmpty {
                out.append(current)
                current = ""
            }
            inWord = isWordChar
            current.append(char)
        }
        if !current.isEmpty { out.append(current) }
        return out
    }

    #if DEBUG
    public static func selfCheck() {
        assert(wordToIpa(["DH", "AH0"]) == "\u{f0}\u{259}")
        // monosyllables carry no stress
        assert(!wordToIpa(["K", "AE1", "T"]).contains("\u{02c8}"))
        assert(wordToIpa(["AH0", "B", "S", "T", "EY1", "N"]).contains("\u{02c8}"))
        let tokens = transcribe("hi, there") { _ in nil }
        assert(tokens.count == 3)
        if case .other(let value) = tokens[1] { assert(value == ", ") } else { assert(false) }
        // non-ASCII letters pass through instead of being guessed at
        assert(text(transcribe("caf\u{e9}") { _ in nil }).hasSuffix("\u{e9}"))
    }
    #endif
}

public enum IPADictionary {

    /// Core plus full CMU pronunciations, read off the main actor.
    public static func load() async -> [String: [String]] {
        await Task.detached(priority: .userInitiated) {
            // full first: it is 10x the core and wins on any shared word
            var merged = read("shavian-dictionary-full")
            for (word, phones) in read("shavian-dictionary-core") where merged[word] == nil {
                merged[word] = phones
            }
            return merged
        }.value
    }

    private static func read(_ name: String) -> [String: [String]] {
        guard let url = Bundle.module.url(forResource: name, withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let parsed = try? JSONDecoder().decode([String: [String]].self, from: data)
        else { return [:] }
        return parsed
    }
}
