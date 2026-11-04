import Foundation


public struct ShavianLetter: Sendable {
    public let shavian: String
    public let name: String
    public let ipa: String
    public let category: Category

    public enum Category: Sendable { case consonant, vowel }
}

public enum ShavianPhonemeMap {

    public static let letters: [ShavianLetter] = [
        // Tall consonants (unvoiced)
        ShavianLetter(shavian: "𐑐", name: "peep", ipa: "p", category: .consonant),
        ShavianLetter(shavian: "𐑑", name: "tot", ipa: "t", category: .consonant),
        ShavianLetter(shavian: "𐑒", name: "kick", ipa: "k", category: .consonant),
        ShavianLetter(shavian: "𐑓", name: "fee", ipa: "f", category: .consonant),
        ShavianLetter(shavian: "𐑔", name: "thigh", ipa: "θ", category: .consonant),
        ShavianLetter(shavian: "𐑕", name: "so", ipa: "s", category: .consonant),
        ShavianLetter(shavian: "𐑖", name: "sure", ipa: "ʃ", category: .consonant),
        ShavianLetter(shavian: "𐑗", name: "church", ipa: "tʃ", category: .consonant),
        // Deep consonants (voiced)
        ShavianLetter(shavian: "𐑚", name: "bib", ipa: "b", category: .consonant),
        ShavianLetter(shavian: "𐑛", name: "dead", ipa: "d", category: .consonant),
        ShavianLetter(shavian: "𐑜", name: "gag", ipa: "ɡ", category: .consonant),
        ShavianLetter(shavian: "𐑝", name: "vow", ipa: "v", category: .consonant),
        ShavianLetter(shavian: "𐑞", name: "they", ipa: "ð", category: .consonant),
        ShavianLetter(shavian: "𐑟", name: "zoo", ipa: "z", category: .consonant),
        ShavianLetter(shavian: "𐑠", name: "measure", ipa: "ʒ", category: .consonant),
        ShavianLetter(shavian: "𐑡", name: "judge", ipa: "dʒ", category: .consonant),
        // Tall sonorants
        ShavianLetter(shavian: "𐑘", name: "yea", ipa: "j", category: .consonant),
        ShavianLetter(shavian: "𐑢", name: "woe", ipa: "w", category: .consonant),
        // Deep sonorants
        ShavianLetter(shavian: "𐑙", name: "hung", ipa: "ŋ", category: .consonant),
        ShavianLetter(shavian: "𐑣", name: "ha-ha", ipa: "h", category: .consonant),
        // Nasals and liquids
        ShavianLetter(shavian: "𐑥", name: "mime", ipa: "m", category: .consonant),
        ShavianLetter(shavian: "𐑯", name: "nun", ipa: "n", category: .consonant),
        ShavianLetter(shavian: "𐑤", name: "loll", ipa: "l", category: .consonant),
        ShavianLetter(shavian: "𐑮", name: "roar", ipa: "r", category: .consonant),
        // Short vowels
        ShavianLetter(shavian: "𐑨", name: "ash", ipa: "æ", category: .vowel),
        ShavianLetter(shavian: "𐑩", name: "ado", ipa: "ə", category: .vowel),
        ShavianLetter(shavian: "𐑪", name: "on", ipa: "ɒ", category: .vowel),
        ShavianLetter(shavian: "𐑫", name: "wool", ipa: "ʊ", category: .vowel),
        ShavianLetter(shavian: "𐑦", name: "if", ipa: "ɪ", category: .vowel),
        ShavianLetter(shavian: "𐑧", name: "egg", ipa: "ɛ", category: .vowel),
        ShavianLetter(shavian: "𐑳", name: "up", ipa: "ʌ", category: .vowel),
        // Long vowels
        ShavianLetter(shavian: "𐑱", name: "ate", ipa: "eɪ", category: .vowel),
        ShavianLetter(shavian: "𐑰", name: "eat", ipa: "iː", category: .vowel),
        ShavianLetter(shavian: "𐑲", name: "ice", ipa: "aɪ", category: .vowel),
        ShavianLetter(shavian: "𐑴", name: "oak", ipa: "oʊ", category: .vowel),
        ShavianLetter(shavian: "𐑵", name: "ooze", ipa: "uː", category: .vowel),
        ShavianLetter(shavian: "𐑶", name: "oil", ipa: "ɔɪ", category: .vowel),
        ShavianLetter(shavian: "𐑬", name: "out", ipa: "aʊ", category: .vowel),
        ShavianLetter(shavian: "𐑷", name: "awe", ipa: "ɔː", category: .vowel),
        ShavianLetter(shavian: "𐑸", name: "are", ipa: "ɑːr", category: .vowel),
        ShavianLetter(shavian: "𐑹", name: "or", ipa: "ɔːr", category: .vowel),
        ShavianLetter(shavian: "𐑺", name: "air", ipa: "ɛər", category: .vowel),
        ShavianLetter(shavian: "𐑻", name: "err", ipa: "ɜːr", category: .vowel),
        ShavianLetter(shavian: "𐑼", name: "array", ipa: "ɚ", category: .vowel),
        ShavianLetter(shavian: "𐑽", name: "ear", ipa: "ɪər", category: .vowel),
        ShavianLetter(shavian: "𐑾", name: "ian", ipa: "ɪə", category: .vowel),
        ShavianLetter(shavian: "𐑿", name: "yew", ipa: "juː", category: .vowel),
    ]

    public static let arpabetToShavian: [String: String] = [
        // Consonants
        "P": "𐑐", "T": "𐑑", "K": "𐑒", "F": "𐑓",
        "TH": "𐑔", "S": "𐑕", "SH": "𐑖", "CH": "𐑗",
        "B": "𐑚", "D": "𐑛", "G": "𐑜", "V": "𐑝",
        "DH": "𐑞", "Z": "𐑟", "ZH": "𐑠", "JH": "𐑡",
        "Y": "𐑘", "W": "𐑢", "NG": "𐑙", "HH": "𐑣",
        "M": "𐑥", "N": "𐑯", "L": "𐑤", "R": "𐑮",
        // Vowels
        "AE": "𐑨", "AH0": "𐑩", "AH": "𐑳", "AA": "𐑪", "AA_PALM": "𐑭",
        "UH": "𐑫", "IH": "𐑦", "EH": "𐑧",
        "EY": "𐑱", "IY": "𐑰", "IY0": "𐑦", "AY": "𐑲",
        "OW": "𐑴", "UW": "𐑵", "OY": "𐑶",
        "AW": "𐑬", "AO": "𐑷",
        "ER": "𐑼",
        // Merged sequences
        "YUW": "𐑿",
    ]

    public static let arpabetToIpa: [String: String] = [
        "P": "p", "T": "t", "K": "k", "F": "f",
        "TH": "θ", "S": "s", "SH": "ʃ", "CH": "tʃ",
        "B": "b", "D": "d", "G": "ɡ", "V": "v",
        "DH": "ð", "Z": "z", "ZH": "ʒ", "JH": "dʒ",
        "Y": "j", "W": "w", "NG": "ŋ", "HH": "h",
        "M": "m", "N": "n", "L": "l", "R": "r",
        "AE": "æ", "AH0": "ə", "AH": "ʌ", "AA": "ɒ", "AA_PALM": "ɑː",
        "UH": "ʊ", "IH": "ɪ", "EH": "ɛ",
        "EY": "eɪ", "IY": "iː", "IY0": "i", "AY": "aɪ",
        "OW": "oʊ", "UW": "uː", "OY": "ɔɪ",
        "AW": "aʊ", "AO": "ɔː",
        "ER": "ɚ",
        "YUW": "juː",
    ]

    public static let consonantGroups: [[String]] = [
        ["𐑐", "𐑚"],       // peep / bib
        ["𐑑", "𐑛"],       // tot / dead
        ["𐑒", "𐑜"],       // kick / gag
        ["𐑓", "𐑝"],       // fee / vow
        ["𐑔", "𐑞"],       // thigh / they
        ["𐑕", "𐑟"],       // so / zoo
        ["𐑖", "𐑠"],       // sure / measure
        ["𐑗", "𐑡"],       // church / judge
        ["𐑥", "𐑯", "𐑙"], // mime / nun / hung (nasals)
        ["𐑤", "𐑮"],       // loll / roar (liquids)
        ["𐑘", "𐑢"],       // yea / woe (glides)
        ["𐑣"],             // ha-ha (alone)
    ]

    public static let vowelChars: [String] = letters
        .filter { $0.category == .vowel }
        .map(\.shavian)

    private static let byChar: [String: ShavianLetter] = {
        Dictionary(uniqueKeysWithValues: letters.map { ($0.shavian, $0) })
    }()

    public static func letter(for char: String) -> ShavianLetter? { byChar[char] }

    /// Normalize ARPABET: AH0 stays AH0 (schwa), AH1/AH2 become AH (strut),
    /// IY0 stays IY0 (kit), strip trailing digits otherwise.
    public static func normalizeArpabet(_ code: String) -> String {
        if code.hasPrefix("AH") {
            return code.hasSuffix("0") ? "AH0" : "AH"
        }
        if code.hasPrefix("IY") {
            return code.hasSuffix("0") ? "IY0" : "IY"
        }
        if let last = code.last, "012".contains(last) {
            return String(code.dropLast())
        }
        return code
    }

    public static func shavianChar(for arpabet: String) -> String? {
        arpabetToShavian[normalizeArpabet(arpabet)]
    }

    public static func ipaString(for arpabet: String) -> String? {
        arpabetToIpa[normalizeArpabet(arpabet)]
    }
}


public struct ShavianAlternative: Sendable {
    public let shavian: String
    public let name: String
    public let ipa: String
}

public enum ShavianAlternatives {

    /// Maps a consonant character to its voicing/articulation group (excluding itself).
    private static let consonantGroupMap: [String: [String]] = {
        var map: [String: [String]] = [:]
        for group in ShavianPhonemeMap.consonantGroups {
            for char in group {
                map[char] = group.filter { $0 != char }
            }
        }
        return map
    }()

    /// Get alternative Shavian letters for a given character.
    /// - Vowels: all other vowel characters
    /// - Consonants: voicing pair / articulation group members
    public static func alternatives(for shavianChar: String) -> [ShavianAlternative] {
        guard let letter = ShavianPhonemeMap.letter(for: shavianChar) else { return [] }

        let candidates: [String]

        if letter.category == .vowel {
            candidates = ShavianPhonemeMap.vowelChars.filter { $0 != shavianChar }
        } else {
            candidates = consonantGroupMap[shavianChar] ?? []
        }

        return candidates.compactMap { c in
            guard let l = ShavianPhonemeMap.letter(for: c) else { return nil }
            return ShavianAlternative(shavian: l.shavian, name: l.name, ipa: l.ipa)
        }
    }
}


public enum ShavianHeuristic {

    public struct HeuristicPhoneme {
        public let shavian: String
        public let ipa: String
    }

    private static let graphemeRules: [(String, String)] = [
        // Multi-character patterns (longest first)
        ("tion", "𐑖𐑩𐑯"),
        ("sion", "𐑠𐑩𐑯"),
        ("ture", "𐑗𐑼"),
        ("ough", "𐑴"),      // most common: "though" — user can fix others
        ("ight", "𐑲𐑑"),
        ("ould", "𐑫𐑛"),
        ("ious", "𐑾𐑕"),
        ("eous", "𐑾𐑕"),
        ("tch", "𐑗"),
        ("dge", "𐑡"),
        ("sch", "𐑕𐑒"),
        ("scr", "𐑕𐑒𐑮"),
        ("shr", "𐑖𐑮"),
        ("thr", "𐑔𐑮"),
        ("str", "𐑕𐑑𐑮"),
        ("spl", "𐑕𐑐𐑤"),
        ("spr", "𐑕𐑐𐑮"),
        ("kn", "𐑯"),
        ("wr", "𐑮"),
        ("gn", "𐑯"),
        ("ph", "𐑓"),
        ("wh", "𐑢"),
        ("gh", ""),           // silent in most positions
        ("th", "𐑔"),         // default to unvoiced; user can swap
        ("sh", "𐑖"),
        ("ch", "𐑗"),
        ("ng", "𐑙"),
        ("nk", "𐑙𐑒"),
        ("qu", "𐑒𐑢"),
        ("ck", "𐑒"),
        ("ee", "𐑰"),
        ("ea", "𐑰"),
        ("oo", "𐑵"),
        ("ou", "𐑬"),
        ("ow", "𐑬"),
        ("oi", "𐑶"),
        ("oy", "𐑶"),
        ("ai", "𐑱"),
        ("ay", "𐑱"),
        ("ei", "𐑱"),
        ("ey", "𐑱"),
        ("ie", "𐑰"),
        ("aw", "𐑷"),
        ("au", "𐑷"),
        ("er", "𐑼"),
        ("ir", "𐑻"),
        ("ur", "𐑻"),
        ("or", "𐑹"),
        ("ar", "𐑸"),
        ("ew", "𐑿"),
        // Single-letter fallbacks
        ("a", "𐑨"),
        ("b", "𐑚"),
        ("c", "𐑒"),
        ("d", "𐑛"),
        ("e", "𐑧"),          // short e default; often silent at word end (handled separately)
        ("f", "𐑓"),
        ("g", "𐑜"),
        ("h", "𐑣"),
        ("i", "𐑦"),
        ("j", "𐑡"),
        ("k", "𐑒"),
        ("l", "𐑤"),
        ("m", "𐑥"),
        ("n", "𐑯"),
        ("o", "𐑪"),
        ("p", "𐑐"),
        ("r", "𐑮"),
        ("s", "𐑕"),
        ("t", "𐑑"),
        ("u", "𐑳"),
        ("v", "𐑝"),
        ("w", "𐑢"),
        ("x", "𐑒𐑕"),
        ("y", "𐑘"),
        ("z", "𐑟"),
    ]

    /// Convert an English word to Shavian using grapheme rules.
    /// Returns an array of phonemes (one per matched pattern).
    /// This is a rough heuristic — results should be flagged for user review.
    public static func transliterate(_ word: String) -> [HeuristicPhoneme] {
        let lower = word.lowercased()
        var result: [HeuristicPhoneme] = []
        var i = lower.startIndex

        // Strip silent trailing 'e' (very rough heuristic)
        let effective: Substring
        if lower.count > 2,
           lower.hasSuffix("e"),
           let penultimate = lower.index(lower.endIndex, offsetBy: -2, limitedBy: lower.startIndex),
           !"aeiouy".contains(lower[penultimate])
        {
            effective = lower[lower.startIndex..<lower.index(before: lower.endIndex)]
        } else {
            effective = lower[...]
        }

        while i < effective.endIndex {
            var matched = false

            for (grapheme, shavianStr) in graphemeRules {
                let remaining = effective[i...]
                if remaining.hasPrefix(grapheme) {
                    if !shavianStr.isEmpty {
                        // Shavian chars are in the supplementary plane — iterate Unicode scalars properly
                        for char in shavianStr {
                            let charStr = String(char)
                            if let letter = ShavianPhonemeMap.letter(for: charStr) {
                                result.append(HeuristicPhoneme(shavian: letter.shavian, ipa: letter.ipa))
                            }
                        }
                    }
                    i = effective.index(i, offsetBy: grapheme.count)
                    matched = true
                    break
                }
            }

            if !matched {
                // Skip unknown characters (numbers, hyphens, etc.)
                i = effective.index(after: i)
            }
        }

        return result
    }
}


public struct ShavianPhoneme {
    public let shavian: String
    public let ipa: String
    public let alternatives: [ShavianAlternative]
}

public struct GlossWord {
    public let latin: String
    public var phonemes: [ShavianPhoneme]
    public var shavian: String
    public var ipa: String
    public var source: Source
    public var marker: Marker
    public var userEdited: Bool

    public enum Source { case core, full, heuristic, shorthand }

    public enum Marker: CaseIterable {
        case none, namer, acroring, acroarc
    }
}

public enum GlossToken {
    case word(GlossWord)
    case punctuation(String)
    case whitespace(String)
}

@MainActor
public final class ShavianEngine {
    public init() {}

    private var coreDictionary: [String: [String]] = [:]
    private var fullDictionary: [String: [String]] = [:]

    private static let shorthands: [String: (shavian: String, ipa: String)] = [
        "the": ("𐑞", "ðə"),
        "of":  ("𐑝", "əv"),
        "and": ("𐑯", "ənd"),
        "to":  ("𐑑", "tuː"),
        "for": ("𐑓", "fɔːr"),
    ]

    private static let arpabetOverrides: [String: [(from: String, to: String)]] = {
        var map: [String: [(from: String, to: String)]] = [:]

        // PALM words: AA → AA_PALM (𐑭, IPA ɑː)
        let palmWords = [
            "father", "rather", "lather",
            "calm", "palm", "psalm", "balm", "almond",
            "drama", "banana", "llama", "mama", "papa",
            "lava", "java", "guava",
            "rajah", "hurrah", "aha", "bah",
            "salami", "safari", "tsunami", "khaki",
            "spa", "bra",
            "pasta", "plaza", "taco",
            "cantata", "sonata", "aria",
        ]
        for w in palmWords {
            map[w] = [(from: "AA", to: "AA_PALM")]
        }

        // THOUGHT bugs: AA → AO (𐑷, IPA ɔː)
        let thoughtWords = ["caught", "bought", "raw", "spawn", "cause"]
        for w in thoughtWords {
            map[w] = [(from: "AA", to: "AO")]
        }

        return map
    }()

    public func loadCoreDictionary() {
        guard let url = Bundle.module.url(
            forResource: "shavian-dictionary-core",
            withExtension: "json"
        ) else { return }
        coreDictionary = Self.parseDictionary(at: url)
    }

    public func loadFullDictionary() async {
        guard let url = Bundle.module.url(
            forResource: "shavian-dictionary-full",
            withExtension: "json"
        ) else { return }
        let dict = await Task.detached { Self.parseDictionary(at: url) }.value
        fullDictionary = dict
    }

    private nonisolated static func parseDictionary(at url: URL) -> [String: [String]] {
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: [String]]
        else { return [:] }
        return json
    }

    private static let tokenRegex = try! NSRegularExpression(
        pattern: #"([a-zA-Z']+)|(\s+)|([^\sa-zA-Z']+)"#
    )

    public func tokenise(_ text: String) -> [GlossToken] {
        var tokens: [GlossToken] = []
        let nsRange = NSRange(text.startIndex..., in: text)

        Self.tokenRegex.enumerateMatches(in: text, range: nsRange) { match, _, _ in
            guard let match else { return }

            if let range = Range(match.range(at: 1), in: text) {
                let word = String(text[range])
                let gloss = transliterateWord(word)
                tokens.append(.word(gloss))
            } else if let range = Range(match.range(at: 2), in: text) {
                tokens.append(.whitespace(String(text[range])))
            } else if let range = Range(match.range(at: 3), in: text) {
                tokens.append(.punctuation(String(text[range])))
            }
        }

        return tokens
    }

    private func transliterateWord(_ word: String) -> GlossWord {
        let lower = word.lowercased()

        if let shorthand = Self.shorthands[lower] {
            let phoneme = ShavianPhoneme(
                shavian: shorthand.shavian,
                ipa: shorthand.ipa,
                alternatives: ShavianAlternatives.alternatives(for: shorthand.shavian)
            )
            return GlossWord(
                latin: word,
                phonemes: [phoneme],
                shavian: shorthand.shavian,
                ipa: shorthand.ipa,
                source: .shorthand,
                marker: .none,
                userEdited: false
            )
        }

        if let lookup = dictionaryLookup(lower) {
            let corrected = Self.applyArpabetOverrides(word: lower, arpabets: lookup.arpabets)
            let phonemes = Self.arpabetToPhonemes(corrected)
            return GlossWord(
                latin: word,
                phonemes: phonemes,
                shavian: phonemes.map(\.shavian).joined(),
                ipa: phonemes.map(\.ipa).joined(),
                source: lookup.source,
                marker: .none,
                userEdited: false
            )
        }

        let heuristic = ShavianHeuristic.transliterate(word)
        let phonemes: [ShavianPhoneme] = heuristic.map { h in
            ShavianPhoneme(
                shavian: h.shavian,
                ipa: h.ipa,
                alternatives: ShavianAlternatives.alternatives(for: h.shavian)
            )
        }
        return GlossWord(
            latin: word,
            phonemes: phonemes,
            shavian: phonemes.map(\.shavian).joined(),
            ipa: phonemes.map(\.ipa).joined(),
            source: .heuristic,
            marker: .none,
            userEdited: false
        )
    }

    public func reResolveTokens(_ tokens: [GlossToken]) -> [GlossToken] {
        tokens.map { token in
            guard case .word(let gloss) = token else { return token }
            guard !gloss.userEdited, gloss.source == .heuristic else { return token }

            guard let lookup = dictionaryLookup(gloss.latin.lowercased()) else { return token }

            let corrected = Self.applyArpabetOverrides(word: gloss.latin, arpabets: lookup.arpabets)
            let phonemes = Self.arpabetToPhonemes(corrected)
            let prefix = Self.markerPrefix(gloss.marker)

            var updated = gloss
            updated.phonemes = phonemes
            updated.shavian = prefix + phonemes.map(\.shavian).joined()
            updated.ipa = phonemes.map(\.ipa).joined()
            updated.source = lookup.source
            return .word(updated)
        }
    }

    /// prefix and suffix matching
    public static func carryEdits(from old: [GlossToken], to new: [GlossToken]) -> [GlossToken] {
        let before: [GlossWord] = old.compactMap { if case .word(let gloss) = $0 { gloss } else { nil } }
        let slots = new.indices.filter { if case .word = new[$0] { true } else { false } }
        func latin(_ slot: Int) -> String { if case .word(let gloss) = new[slot] { gloss.latin } else { "" } }
        var out = new
        func carry(_ gloss: GlossWord, to slot: Int) {
            if gloss.userEdited || gloss.marker != .none { out[slot] = .word(gloss) }
        }
        let shared = min(before.count, slots.count)
        var prefix = 0
        while prefix < shared, before[prefix].latin == latin(slots[prefix]) {
            carry(before[prefix], to: slots[prefix])
            prefix += 1
        }
        var suffix = 0
        while suffix < shared - prefix, before[before.count - 1 - suffix].latin == latin(slots[slots.count - 1 - suffix]) {
            carry(before[before.count - 1 - suffix], to: slots[slots.count - 1 - suffix])
            suffix += 1
        }
        return out
    }

    public static func inserting(_ letter: ShavianLetter, at index: Int, in word: GlossWord) -> GlossWord {
        var word = word
        let phoneme = ShavianPhoneme(
            shavian: letter.shavian, ipa: letter.ipa, alternatives: ShavianAlternatives.alternatives(for: letter.shavian)
        )
        word.phonemes.insert(phoneme, at: min(max(0, index), word.phonemes.count))
        return respelled(word)
    }

    public static func removing(at index: Int, in word: GlossWord) -> GlossWord? {
        guard word.phonemes.count > 1, word.phonemes.indices.contains(index) else { return nil }
        var word = word
        word.phonemes.remove(at: index)
        return respelled(word)
    }

    private static func respelled(_ word: GlossWord) -> GlossWord {
        var word = word
        word.shavian = markerPrefix(word.marker) + word.phonemes.map(\.shavian).joined()
        word.ipa = word.phonemes.map(\.ipa).joined()
        word.userEdited = true
        return word
    }

    #if DEBUG
    public static func selfCheck() {
        func word(_ latin: String, _ marker: GlossWord.Marker = .none) -> GlossToken {
            .word(GlossWord(latin: latin, phonemes: [], shavian: latin, ipa: "", source: .core, marker: marker, userEdited: false))
        }
        func markers(_ tokens: [GlossToken]) -> [GlossWord.Marker] {
            tokens.compactMap { if case .word(let gloss) = $0 { gloss.marker } else { nil } }
        }
        let old = [word("Shaw", .namer), .whitespace(" "), word("wrote"), .whitespace(" "), word("NATO", .acroarc)]
        let typed = [word("Shaw"), .whitespace(" "), word("never"), .whitespace(" "), word("wrote"), .whitespace(" "), word("NATO")]
        assert(markers(carryEdits(from: old, to: typed)) == [.namer, .none, .none, .acroarc])
        let changed = [word("Shah"), .whitespace(" "), word("wrote"), .whitespace(" "), word("NATO")]
        assert(markers(carryEdits(from: old, to: changed)) == [.none, .none, .acroarc])
        assert(carryEdits(from: old, to: []).isEmpty)

        let letter = { ShavianPhonemeMap.letter(for: $0)! }
        let shaw = inserting(letter("𐑖"), at: 0, in: GlossWord(latin: "Shaw", phonemes: [], shavian: "", ipa: "", source: .core, marker: .namer, userEdited: false))
        let shaws = inserting(letter("𐑟"), at: 2, in: inserting(letter("𐑷"), at: 1, in: shaw))
        assert(shaws.shavian == "·𐑖𐑷𐑟" && shaws.ipa == "ʃɔːz" && shaws.userEdited)
        assert(inserting(letter("𐑩"), at: 0, in: shaws).shavian == "·𐑩𐑖𐑷𐑟")
        assert(inserting(letter("𐑩"), at: 1, in: shaws).shavian == "·𐑖𐑩𐑷𐑟")
        assert(removing(at: 2, in: shaws)?.shavian == "·𐑖𐑷")
        assert(removing(at: 0, in: shaw) == nil)
        let retyped = carryEdits(from: [.word(shaws)], to: [.word(shaw), .whitespace(" "), .word(shaw)])
        if case .word(let kept) = retyped[0] { assert(kept.shavian == "·𐑖𐑷𐑟") } else { assert(false) }
    }
    #endif

    public static func markerPrefix(_ marker: GlossWord.Marker) -> String {
        switch marker {
        case .none: ""
        case .namer: "·"
        case .acroring: "⸰"
        case .acroarc: "꤮"
        }
    }

    private func dictionaryLookup(_ word: String) -> (arpabets: [String], source: GlossWord.Source)? {
        if let core = coreDictionary[word] { return (core, .core) }
        if let full = fullDictionary[word] { return (full, .full) }
        return nil
    }

    private static func applyArpabetOverrides(word: String, arpabets: [String]) -> [String] {
        guard let overrides = arpabetOverrides[word.lowercased()] else { return arpabets }
        return arpabets.map { code in
            let base = ShavianPhonemeMap.normalizeArpabet(code)
            if let override = overrides.first(where: { $0.from == base }) {
                return override.to
            }
            return code
        }
    }

    /// Merge ARPABET sequences that map to single Shavian letters.
    /// e.g. Y + UW → YUW (yew ligature 𐑿)
    private static func mergeArpabetSequences(_ arpabets: [String]) -> [String] {
        var result: [String] = []
        var i = 0
        while i < arpabets.count {
            if arpabets[i] == "Y",
               i + 1 < arpabets.count,
               ShavianPhonemeMap.normalizeArpabet(arpabets[i + 1]) == "UW"
            {
                result.append("YUW")
                i += 2
            } else {
                result.append(arpabets[i])
                i += 1
            }
        }
        return result
    }

    private static func arpabetToPhonemes(_ arpabets: [String]) -> [ShavianPhoneme] {
        let merged = mergeArpabetSequences(arpabets)
        return merged.map { code in
            let shavian = ShavianPhonemeMap.shavianChar(for: code) ?? "?"
            let ipa = ShavianPhonemeMap.ipaString(for: code) ?? "?"
            return ShavianPhoneme(
                shavian: shavian,
                ipa: ipa,
                alternatives: ShavianAlternatives.alternatives(for: shavian)
            )
        }
    }
}


/// The transliterator's state: the tokens of the input with the user's edits, and how far the dictionaries have loaded.
@MainActor
public final class ShavianTransliteration {
    public enum DictStatus { case loadingCore, loadingFull, ready }

    public var input = ""
    public var tokens: [GlossToken] = [] {
        didSet { onChange?() }
    }
    public private(set) var dictStatus = DictStatus.loadingCore {
        didSet { onChange?() }
    }
    public var onChange: (() -> Void)?

    private let engine = ShavianEngine()

    public init() {}

    public func loadDictionaries() {
        engine.loadCoreDictionary()
        dictStatus = .loadingFull
        retokenise()
        Task {
            await engine.loadFullDictionary()
            tokens = engine.reResolveTokens(tokens)
            dictStatus = .ready
        }
    }

    public func retokenise() {
        tokens = ShavianEngine.carryEdits(from: tokens, to: engine.tokenise(input))
    }

    public func setMarker(tokenIndex: Int, marker: GlossWord.Marker) {
        guard tokens.indices.contains(tokenIndex), case .word(var gloss) = tokens[tokenIndex], gloss.marker != marker else { return }
        gloss.marker = marker
        gloss.shavian = ShavianEngine.markerPrefix(marker) + gloss.phonemes.map(\.shavian).joined()
        tokens[tokenIndex] = .word(gloss)
    }

    public func swapPhoneme(tokenIndex: Int, phonemeIndex: Int, alternative: ShavianAlternative) {
        guard tokens.indices.contains(tokenIndex), case .word(var gloss) = tokens[tokenIndex],
              gloss.phonemes.indices.contains(phonemeIndex) else { return }
        gloss.phonemes[phonemeIndex] = ShavianPhoneme(
            shavian: alternative.shavian, ipa: alternative.ipa, alternatives: ShavianAlternatives.alternatives(for: alternative.shavian)
        )
        gloss.shavian = ShavianEngine.markerPrefix(gloss.marker) + gloss.phonemes.map(\.shavian).joined()
        gloss.ipa = gloss.phonemes.map(\.ipa).joined()
        gloss.userEdited = true
        tokens[tokenIndex] = .word(gloss)
    }

    public func insertPhoneme(tokenIndex: Int, at index: Int, letter: ShavianLetter) {
        guard tokens.indices.contains(tokenIndex), case .word(let gloss) = tokens[tokenIndex] else { return }
        tokens[tokenIndex] = .word(ShavianEngine.inserting(letter, at: index, in: gloss))
    }

    public func removePhoneme(tokenIndex: Int, at index: Int) {
        guard tokens.indices.contains(tokenIndex), case .word(let gloss) = tokens[tokenIndex],
              let removed = ShavianEngine.removing(at: index, in: gloss) else { return }
        tokens[tokenIndex] = .word(removed)
    }

    public var shavianText: String {
        tokens.map { token in
            switch token {
            case .word(let gloss): gloss.shavian
            case .punctuation(let value), .whitespace(let value): value
            }
        }.joined()
    }
}
