import Foundation

public enum PasswordEngine {

    public static let lowercaseSet = "abcdefghijklmnopqrstuvwxyz"
    public static let uppercaseSet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
    public static let digitSet = "0123456789"
    // safe to paste anywhere
    public static let symbolSet = "!@#$%^&*()-=_+?[]{};:,.<>/~"
    // keepassxc ambiguous set
    public static let ambiguous = "Il1O0"

    public static let minimumLength = 8
    public static let maximumLength = 128
    public static let minimumWords = 3
    public static let maximumWords = 10

    public struct PasswordSpec {
        public var length = 16
        public var lowercase = true
        public var uppercase = true
        public var digits = true
        public var symbols = true
        public var excludeAmbiguous = true

        public init() {}
    }

    public struct PassphraseSpec {
        public var words = 5
        public var separator = "-"
        public var capitaliseFirst = true
        public var trailingDigit = true

        public init() {}
    }

    public enum CharKind { case letter, digit, symbol }

    public static func kind(of char: Character) -> CharKind {
        if digitSet.contains(char) { return .digit }
        if symbolSet.contains(char) { return .symbol }
        return .letter
    }

    public static func charset(_ spec: PasswordSpec) -> [Character] {
        var pool = ""
        if spec.lowercase { pool += lowercaseSet }
        if spec.uppercase { pool += uppercaseSet }
        if spec.digits { pool += digitSet }
        if spec.symbols { pool += symbolSet }
        if spec.excludeAmbiguous { pool = pool.filter { !ambiguous.contains($0) } }
        return Array(pool)
    }

    // randomElement: system csprng, unbiased
    public static func password(_ spec: PasswordSpec) -> String {
        let pool = charset(spec)
        guard !pool.isEmpty else { return "" }
        let length = min(maximumLength, max(minimumLength, spec.length))
        return String((0..<length).compactMap { _ in pool.randomElement() })
    }

    public static func passphrase(_ wordlist: [String], spec: PassphraseSpec) -> String {
        guard !wordlist.isEmpty else { return "" }
        let count = min(maximumWords, max(minimumWords, spec.words))
        var picked = (0..<count).compactMap { _ in wordlist.randomElement() }
        if spec.capitaliseFirst, let first = picked.first {
            picked[0] = first.prefix(1).uppercased() + first.dropFirst()
        }
        var out = picked.joined(separator: spec.separator)
        if spec.trailingDigit { out += String(Int.random(in: 0...9)) }
        return out
    }

    public static func passwordEntropy(length: Int, poolSize: Int) -> Double {
        guard poolSize >= 2 else { return 0 }
        return Double(length) * log2(Double(poolSize))
    }

    public static func passphraseEntropy(words: Int, wordlistSize: Int, trailingDigit: Bool) -> Double {
        guard wordlistSize >= 2 else { return 0 }
        return Double(words) * log2(Double(wordlistSize)) + (trailingDigit ? log2(10) : 0)
    }

    public static func strengthBand(_ bits: Double) -> String {
        switch bits {
        case 95...: String(localized: "Very strong")
        case 60...: String(localized: "Strong")
        case 40...: String(localized: "Fair")
        default: String(localized: "Weak")
        }
    }

    /// EFF dice wordlist: a roll code, a tab, then the word.
    public static func parseWordlist(_ text: String) -> [String] {
        text.split(separator: "\n", omittingEmptySubsequences: false).compactMap { line in
            let word = line.drop { $0.isWhitespace }
                .drop { $0.isNumber }
                .trimmingCharacters(in: .whitespaces)
                .lowercased()
            guard !word.isEmpty, word.allSatisfy({ ("a"..."z").contains($0) }) else { return nil }
            return word
        }
    }

    public static func loadWordlist() async -> [String] {
        await Task.detached(priority: .userInitiated) {
            guard let url = Bundle.main.url(forResource: "password-eff-wordlist", withExtension: "txt"),
                  let text = try? String(contentsOf: url, encoding: .utf8)
            else { return [] }
            return parseWordlist(text)
        }.value
    }

    #if DEBUG
    public static func selfCheck() {
        assert(parseWordlist("11111\tabacus\n11112\tabdomen\n") == ["abacus", "abdomen"])
        assert(parseWordlist("not a word\n") == [])
        var spec = PasswordSpec()
        spec.length = 20
        assert(password(spec).count == 20)
        spec.length = 2
        assert(password(spec).count == minimumLength)
        spec.length = 500
        assert(password(spec).count == maximumLength)
        var bare = PasswordSpec()
        bare.uppercase = false
        bare.digits = false
        bare.symbols = false
        bare.excludeAmbiguous = false
        assert(charset(bare).count == 26)
        assert(password(bare).allSatisfy { ("a"..."z").contains($0) })
        assert(charset(PasswordSpec()).allSatisfy { !ambiguous.contains($0) })
        assert(abs(passwordEntropy(length: 16, poolSize: 64) - 96) < 0.001)
        assert(strengthBand(0) == String(localized: "Weak") && strengthBand(100) == String(localized: "Very strong"))
        let phrase = passphrase(["alpha", "beta"], spec: PassphraseSpec())
        assert(phrase.split(separator: "-").count == 5)
        assert(kind(of: "3") == .digit && kind(of: "!") == .symbol && kind(of: "a") == .letter)
    }
    #endif
}
