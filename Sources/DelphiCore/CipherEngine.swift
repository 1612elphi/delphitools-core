import Foundation

public nonisolated enum CipherError: LocalizedError, Sendable {
    case affineCoprime
    case base32Character
    case hexLength
    case hexCharacter
    case binaryLength
    case base64Invalid

    public var errorDescription: String? {
        switch self {
        case .affineCoprime: String(localized: "'a' must be coprime with 26 (try 1,3,5,7,9,11,15,17,19,21,23,25).")
        case .base32Character: String(localized: "Invalid Base32 character.")
        case .hexLength: String(localized: "Hex must have even length.")
        case .hexCharacter: String(localized: "Invalid hex character.")
        case .binaryLength: String(localized: "Binary must be a multiple of 8 bits.")
        case .base64Invalid: String(localized: "Invalid Base64.")
        }
    }
}

public nonisolated enum CipherId: String, CaseIterable, Identifiable, Sendable {
    case caesar, rot13, rot47, atbash, vigenere, affine, railFence = "rail-fence"
    case morse, a1z26, bacon
    case base64, base32, hex, binary

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .caesar: String(localized: "Caesar")
        case .rot13: String(localized: "ROT13")
        case .rot47: String(localized: "ROT47")
        case .atbash: String(localized: "Atbash")
        case .vigenere: String(localized: "Vigenère")
        case .affine: String(localized: "Affine")
        case .railFence: String(localized: "Rail fence")
        case .morse: String(localized: "Morse code")
        case .a1z26: String(localized: "A1Z26")
        case .bacon: String(localized: "Bacon's cipher")
        case .base64: String(localized: "Base64")
        case .base32: String(localized: "Base32")
        case .hex: String(localized: "Hex")
        case .binary: String(localized: "Binary")
        }
    }
}

public nonisolated struct CipherParams: Sendable {
    public var caesarShift = 3
    public var vigenereKey = ""
    public var affineA = 5
    public var affineB = 8
    public var rails = 3
}

public nonisolated struct CipherCandidate: Identifiable, Sendable {
    public let id = UUID()
    public let cipher: String
    public let cipherId: CipherId
    public let detail: String
    public let output: String
    public let score: Double
    public var params: CipherParams?
}

public nonisolated enum CipherEngine: Sendable {

    public static let affineCoprimes = [1, 3, 5, 7, 9, 11, 15, 17, 19, 21, 23, 25]

    public static let samples: [(label: String, text: String)] = [
        (String(localized: "Caesar"), "AOL XBPJR IYVDU MVE QBTWZ VCLY AOL SHGF KVN"),
        (String(localized: "ROT13"), "Abj vf gur jvagre bs bhe qvfpbagrag znqr tybevbhf fhzzre"),
        (String(localized: "Vigenère"), "Vsxt tmq wpt aplrrh ha wlpn hzh eys han asn vbkich kzhex ioqqkd ioiw rpklz zict hvg edz dpb rzi"),
        (String(localized: "Morse"), ".... . .-.. .-.. --- / .-- --- .-. .-.. -.."),
        (String(localized: "Hex"), "50 72 69 76 61 63 79 20 69 73 20 70 6f 77 65 72 2e"),
        (String(localized: "Base64"), "VGhlIGNyb3cgZmxpZXMgYXQgbWlkbmlnaHQu"),
    ]

    // MARK: - Scoring

    private static let englishFrequency: [Character: Double] = [
        "A": 8.167, "B": 1.492, "C": 2.782, "D": 4.253, "E": 12.702, "F": 2.228,
        "G": 2.015, "H": 6.094, "I": 6.966, "J": 0.153, "K": 0.772, "L": 4.025,
        "M": 2.406, "N": 6.749, "O": 7.507, "P": 1.929, "Q": 0.095, "R": 5.987,
        "S": 6.327, "T": 9.056, "U": 2.758, "V": 0.978, "W": 2.36, "X": 0.15,
        "Y": 1.974, "Z": 0.074,
    ]

    private static let commonWords: Set<String> = [
        "THE", "BE", "TO", "OF", "AND", "A", "IN", "THAT", "HAVE", "I", "IT",
        "FOR", "NOT", "ON", "WITH", "HE", "AS", "YOU", "DO", "AT", "THIS",
        "BUT", "HIS", "BY", "FROM", "THEY", "WE", "SAY", "HER", "SHE", "OR",
        "AN", "WILL", "MY", "ONE", "ALL", "WOULD", "THERE", "THEIR", "WHAT",
        "SO", "UP", "OUT", "IF", "ABOUT", "WHO", "GET", "WHICH", "GO", "ME",
        "WHEN", "MAKE", "CAN", "LIKE", "TIME", "NO", "JUST", "HIM", "KNOW",
        "TAKE", "PEOPLE", "INTO", "YEAR", "YOUR", "GOOD", "SOME", "COULD",
        "THEM", "SEE", "OTHER", "THAN", "THEN", "NOW", "LOOK", "ONLY", "COME",
        "ITS", "OVER", "THINK", "ALSO", "BACK", "AFTER", "USE", "TWO", "HOW",
        "OUR", "WORK", "FIRST", "WELL", "WAY", "EVEN", "NEW", "WANT", "BECAUSE",
        "ANY", "THESE", "GIVE", "DAY", "MOST", "US", "IS", "WAS", "ARE", "BEEN",
        "HAS", "HAD", "WERE", "SAID",
    ]

    public static func chiSquaredScore(_ text: String) -> Double {
        var counts: [Character: Int] = [:]
        var total = 0
        for char in text.uppercased() where char.isLetter && char.isASCII {
            counts[char, default: 0] += 1
            total += 1
        }
        guard total > 0 else { return .infinity }
        var chi = 0.0
        for (letter, frequency) in englishFrequency {
            let observed = Double(counts[letter] ?? 0)
            let expected = frequency / 100 * Double(total)
            chi += (observed - expected) * (observed - expected) / expected
        }
        return chi
    }

    public static func commonWordRatio(_ text: String) -> Double {
        let words = text.uppercased()
            .split { !($0.isASCII && $0.isLetter) }
            .map(String.init)
        guard !words.isEmpty else { return 0 }
        let hits = words.filter(commonWords.contains).count
        return Double(hits) / Double(words.count)
    }

    public static func englishLikeness(_ text: String) -> Double {
        let letters = text.filter { $0.isASCII && $0.isLetter }
        guard letters.count >= 3 else { return 0 }
        // chi against a hand-picked ceiling
        let chiScore = max(0, 1 - chiSquaredScore(text) / 100)
        let wordScore = min(1, commonWordRatio(text) * 3)
        return chiScore * 0.6 + wordScore * 0.4
    }

    // MARK: - Classical ciphers

    public static func caesarShift(_ text: String, _ shift: Int) -> String {
        let s = ((shift % 26) + 26) % 26
        return String(text.unicodeScalars.map { scalar -> Character in
            let code = Int(scalar.value)
            if code >= 65 && code <= 90 {
                return Character(UnicodeScalar(UInt8((code - 65 + s) % 26 + 65)))
            }
            if code >= 97 && code <= 122 {
                return Character(UnicodeScalar(UInt8((code - 97 + s) % 26 + 97)))
            }
            return Character(scalar)
        })
    }

    public static func rot47(_ text: String) -> String {
        String(text.unicodeScalars.map { scalar -> Character in
            let code = Int(scalar.value)
            guard code >= 33 && code <= 126 else { return Character(scalar) }
            return Character(UnicodeScalar(UInt8(33 + (code - 33 + 47) % 94)))
        })
    }

    public static func atbash(_ text: String) -> String {
        String(text.unicodeScalars.map { scalar -> Character in
            let code = Int(scalar.value)
            if code >= 65 && code <= 90 { return Character(UnicodeScalar(UInt8(90 - (code - 65)))) }
            if code >= 97 && code <= 122 { return Character(UnicodeScalar(UInt8(122 - (code - 97)))) }
            return Character(scalar)
        })
    }

    public static func vigenere(_ text: String, key: String, encode: Bool) -> String {
        let cleanKey = Array(key.uppercased().filter { $0.isASCII && $0.isLetter })
        guard !cleanKey.isEmpty else { return text }
        var out = ""
        var ki = 0
        for scalar in text.unicodeScalars {
            let code = Int(scalar.value)
            let isUpper = code >= 65 && code <= 90
            let isLower = code >= 97 && code <= 122
            guard isUpper || isLower else {
                out.unicodeScalars.append(scalar)
                continue
            }
            let base = isUpper ? 65 : 97
            let shift = Int(cleanKey[ki % cleanKey.count].asciiValue ?? 65) - 65
            let adjust = encode ? shift : -shift
            out.append(Character(UnicodeScalar(UInt8((code - base + adjust + 26) % 26 + base))))
            ki += 1
        }
        return out
    }

    public static func modInverse(_ a: Int, _ m: Int) -> Int? {
        let base = ((a % m) + m) % m
        for x in 1..<m where (base * x) % m == 1 { return x }
        return nil
    }

    public static func affine(_ text: String, a: Int, b: Int, encode: Bool) throws -> String {
        var inverse = 0
        if !encode {
            guard let found = modInverse(a, 26) else { throw CipherError.affineCoprime }
            inverse = found
        }
        var out = ""
        for scalar in text.unicodeScalars {
            let code = Int(scalar.value)
            let isUpper = code >= 65 && code <= 90
            let isLower = code >= 97 && code <= 122
            guard isUpper || isLower else {
                out.unicodeScalars.append(scalar)
                continue
            }
            let base = isUpper ? 65 : 97
            let x = code - base
            let y = encode ? (a * x + b) % 26 : (inverse * ((x - b + 26 * 26) % 26)) % 26
            out.append(Character(UnicodeScalar(UInt8(y + base))))
        }
        return out
    }

    // MARK: - Codes

    public static func morseEncode(_ text: String) -> String {
        chunks(text).map { chunk in
            chunk.isWhitespaceRun
                ? "/"
                : chunk.text.uppercased().compactMap { MorseEngine.table[$0] }.joined(separator: " ")
        }.joined(separator: " ")
    }

    public static func morseDecode(_ text: String) -> String {
        MorseEngine.words(text, minimumGap: 2)
            .map { word in String(word.compactMap { MorseEngine.reverse[$0] }) }
            .joined(separator: " ")
    }

    public static func a1z26Encode(_ text: String) -> String {
        chunks(text).map { chunk in
            chunk.isWhitespaceRun
                ? " / "
                : chunk.text.uppercased()
                    .filter { $0.isASCII && $0.isLetter }
                    .compactMap { letter -> String? in
                        guard let code = letter.asciiValue else { return nil }
                        return String(Int(code) - 64)
                    }
                    .joined(separator: "-")
        }.joined()
    }

    public static func a1z26Decode(_ text: String) -> String {
        MorseEngine.words(text, minimumGap: 2).map { word in
            String(word.flatMap { $0.split { $0 == "-" || $0 == "," } }
                .compactMap { piece -> Character? in
                    // parseInt semantics: leading digits only
                    let leading = piece.prefix { ("0"..."9").contains($0) }
                    guard let value = Int(leading), value >= 1, value <= 26 else { return nil }
                    return Character(UnicodeScalar(UInt8(64 + value)))
                })
        }.joined(separator: " ")
    }

    public static let bacon: [Character: String] = {
        var map: [Character: String] = [:]
        for (index, letter) in "ABCDEFGHIJKLMNOPQRSTUVWXYZ".enumerated() {
            var code = ""
            for bit in 0..<5 { code += (index >> (4 - bit)) & 1 == 1 ? "B" : "A" }
            map[letter] = code
        }
        return map
    }()

    private static let baconReverse: [String: Character] = {
        var map: [String: Character] = [:]
        for (letter, code) in bacon { map[code] = letter }
        return map
    }()

    public static func baconEncode(_ text: String) -> String {
        chunks(text).map { chunk in
            chunk.isWhitespaceRun
                ? " "
                : chunk.text.uppercased()
                    .filter { $0.isASCII && $0.isLetter }
                    .compactMap { bacon[$0] }
                    .joined(separator: " ")
        }.joined()
    }

    public static func baconDecode(_ text: String) -> String {
        let cleaned = Array(text.uppercased().filter { $0 == "A" || $0 == "B" })
        var out = ""
        var i = 0
        while i + 5 <= cleaned.count {
            out.append(baconReverse[String(cleaned[i..<(i + 5)])] ?? "?")
            i += 5
        }
        return out
    }

    // MARK: - Transposition

    // more rails than characters is the same zig-zag as one rail per character
    private static func railCount(_ rails: Int, _ length: Int) -> Int {
        max(2, min(rails, length))
    }

    public static func railFenceEncode(_ text: String, rails: Int) -> String {
        guard rails >= 2, text.count > 1 else { return text }
        let rails = railCount(rails, text.count)
        var fence = Array(repeating: "", count: rails)
        var r = 0
        var direction = 1
        for char in text {
            fence[r].append(char)
            if r == 0 { direction = 1 } else if r == rails - 1 { direction = -1 }
            r += direction
        }
        return fence.joined()
    }

    public static func railFenceDecode(_ text: String, rails: Int) -> String {
        guard rails >= 2, text.count > 1 else { return text }
        let characters = Array(text)
        let rails = railCount(rails, characters.count)
        var pattern: [Int] = []
        var r = 0
        var direction = 1
        for _ in characters {
            pattern.append(r)
            if r == 0 { direction = 1 } else if r == rails - 1 { direction = -1 }
            r += direction
        }
        var counts = Array(repeating: 0, count: rails)
        for row in pattern { counts[row] += 1 }
        var rows: [[Character]] = []
        var index = 0
        for count in counts {
            rows.append(Array(characters[index..<min(index + count, characters.count)]))
            index += count
        }
        var cursors = Array(repeating: 0, count: rails)
        var out = ""
        for row in pattern {
            guard cursors[row] < rows[row].count else { continue }
            out.append(rows[row][cursors[row]])
            cursors[row] += 1
        }
        return out
    }

    // MARK: - Encodings

    public static func base64Encode(_ text: String) -> String {
        Data(text.utf8).base64EncodedString()
    }

    // atob tolerates missing padding
    public static func base64Decode(_ text: String) throws -> String {
        var cleaned = text.filter { !$0.isWhitespace }
        guard cleaned.count % 4 != 1 else { throw CipherError.base64Invalid }
        while cleaned.count % 4 != 0 { cleaned += "=" }
        guard let data = Data(base64Encoded: cleaned) else { throw CipherError.base64Invalid }
        return String(decoding: data, as: UTF8.self)
    }

    private static let base32Alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")

    public static func base32Encode(_ text: String) -> String {
        var bits = ""
        for byte in Data(text.utf8) { bits += eightBits(byte) }
        while bits.count % 5 != 0 { bits += "0" }
        var out = ""
        var index = bits.startIndex
        while index < bits.endIndex {
            let end = bits.index(index, offsetBy: 5)
            out.append(base32Alphabet[Int(bits[index..<end], radix: 2) ?? 0])
            index = end
        }
        while out.count % 8 != 0 { out += "=" }
        return out
    }

    public static func base32Decode(_ text: String) throws -> String {
        var cleaned = text.uppercased().filter { !$0.isWhitespace }
        while cleaned.hasSuffix("=") { cleaned.removeLast() }
        var bits = ""
        for char in cleaned {
            guard let index = base32Alphabet.firstIndex(of: char) else {
                throw CipherError.base32Character
            }
            bits += String(repeating: "0", count: 5 - String(index, radix: 2).count)
                + String(index, radix: 2)
        }
        var bytes: [UInt8] = []
        var index = bits.startIndex
        while bits.distance(from: index, to: bits.endIndex) >= 8 {
            let end = bits.index(index, offsetBy: 8)
            bytes.append(UInt8(bits[index..<end], radix: 2) ?? 0)
            index = end
        }
        return String(decoding: bytes, as: UTF8.self)
    }

    public static func hexEncode(_ text: String) -> String {
        Data(text.utf8).map { String(format: "%02x", $0) }.joined(separator: " ")
    }

    public static func hexDecode(_ text: String) throws -> String {
        var cleaned = text.filter { !$0.isWhitespace }
        if cleaned.lowercased().hasPrefix("0x") { cleaned = String(cleaned.dropFirst(2)) }
        guard cleaned.count % 2 == 0 else { throw CipherError.hexLength }
        var bytes: [UInt8] = []
        var index = cleaned.startIndex
        while index < cleaned.endIndex {
            let end = cleaned.index(index, offsetBy: 2)
            guard let byte = UInt8(cleaned[index..<end], radix: 16) else {
                throw CipherError.hexCharacter
            }
            bytes.append(byte)
            index = end
        }
        return String(decoding: bytes, as: UTF8.self)
    }

    public static func binaryEncode(_ text: String) -> String {
        Data(text.utf8).map(eightBits).joined(separator: " ")
    }

    private static func eightBits(_ byte: UInt8) -> String {
        let bits = String(byte, radix: 2)
        return String(repeating: "0", count: 8 - bits.count) + bits
    }

    public static func binaryDecode(_ text: String) throws -> String {
        let cleaned = Array(text.filter { $0 == "0" || $0 == "1" })
        guard !cleaned.isEmpty, cleaned.count % 8 == 0 else { throw CipherError.binaryLength }
        var bytes: [UInt8] = []
        var i = 0
        while i < cleaned.count {
            bytes.append(UInt8(String(cleaned[i..<(i + 8)]), radix: 2) ?? 0)
            i += 8
        }
        return String(decoding: bytes, as: UTF8.self)
    }

    // MARK: - Vigenère key recovery

    public static func indexOfCoincidence(_ text: String) -> Double {
        var counts = Array(repeating: 0, count: 26)
        var n = 0
        for scalar in text.uppercased().unicodeScalars {
            let code = Int(scalar.value)
            guard code >= 65 && code <= 90 else { continue }
            counts[code - 65] += 1
            n += 1
        }
        guard n >= 2 else { return 0 }
        let sum = counts.reduce(0) { $0 + $1 * ($1 - 1) }
        return Double(sum) / Double(n * (n - 1))
    }

    private static func bestCaesarShiftForGroup(_ group: String) -> Int {
        var bestShift = 0
        var bestChi = Double.infinity
        for s in 0..<26 {
            let chi = chiSquaredScore(caesarShift(group, -s))
            if chi < bestChi {
                bestChi = chi
                bestShift = s
            }
        }
        return bestShift
    }

    public static func guessVigenereKey(_ text: String, maxLength: Int = 10) -> (key: String, ioc: Double)? {
        let letters = Array(text.uppercased().filter { $0.isASCII && $0.isLetter })
        guard letters.count >= 20 else { return nil }

        var iocs: [Double] = [0, 0]
        let upper = min(maxLength, letters.count / 4)
        guard upper >= 2 else { return nil }
        for length in 2...upper {
            var average = 0.0
            for offset in 0..<length {
                var group = ""
                var i = offset
                while i < letters.count {
                    group.append(letters[i])
                    i += length
                }
                average += indexOfCoincidence(group)
            }
            iocs.append(average / Double(length))
        }

        // shortest key near the best index
        let maxIoC = iocs.max() ?? 0
        guard maxIoC >= 0.055 else { return nil }
        var bestLength = 0
        for length in 2...upper where iocs[length] >= maxIoC - 0.008 {
            bestLength = length
            break
        }
        guard bestLength > 0 else { return nil }

        var key = ""
        for offset in 0..<bestLength {
            var group = ""
            var i = offset
            while i < letters.count {
                group.append(letters[i])
                i += bestLength
            }
            key.append(Character(UnicodeScalar(UInt8(65 + bestCaesarShiftForGroup(group)))))
        }
        return (key, iocs[bestLength])
    }

    // MARK: - Manual run

    public static func runManual(_ input: String,
                          cipher: CipherId,
                          encode: Bool,
                          params: CipherParams) throws -> String {
        guard !input.isEmpty else { return "" }
        switch cipher {
        case .caesar: return caesarShift(input, encode ? params.caesarShift : -params.caesarShift)
        case .rot13: return caesarShift(input, 13)
        case .rot47: return rot47(input)
        case .atbash: return atbash(input)
        case .vigenere: return vigenere(input, key: params.vigenereKey, encode: encode)
        case .affine: return try affine(input, a: params.affineA, b: params.affineB, encode: encode)
        case .railFence:
            return encode ? railFenceEncode(input, rails: params.rails)
                          : railFenceDecode(input, rails: params.rails)
        case .morse: return encode ? morseEncode(input) : morseDecode(input)
        case .a1z26: return encode ? a1z26Encode(input) : a1z26Decode(input)
        case .bacon: return encode ? baconEncode(input) : baconDecode(input)
        case .base64: return encode ? base64Encode(input) : try base64Decode(input)
        case .base32: return encode ? base32Encode(input) : try base32Decode(input)
        case .hex: return encode ? hexEncode(input) : try hexDecode(input)
        case .binary: return encode ? binaryEncode(input) : try binaryDecode(input)
        }
    }

    // MARK: - Auto-detection

    // letter frequency and word hits settle long before this much text
    private static let probeLimit = 1500

    public static func classifyAndDecode(_ input: String) -> [CipherCandidate] {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        var candidates: [CipherCandidate] = []
        let bare = trimmed.filter { !$0.isWhitespace }

        if !bare.isEmpty, trimmed.allSatisfy({ ".-/|".contains($0) || $0.isWhitespace }) {
            let out = morseDecode(trimmed)
            if !out.isEmpty {
                candidates.append(CipherCandidate(cipher: String(localized: "Morse code"), cipherId: .morse,
                                                  detail: "", output: out, score: 0.95))
            }
        }

        if bare.count >= 8, trimmed.allSatisfy({ $0 == "0" || $0 == "1" || $0.isWhitespace }),
           let out = try? binaryDecode(trimmed), isReadable(out), englishLikeness(out) > 0.05 {
            candidates.append(CipherCandidate(cipher: String(localized: "Binary"), cipherId: .binary,
                                              detail: "8-bit", output: out, score: 0.9))
        }

        let hexBody = trimmed.lowercased().hasPrefix("0x") ? String(trimmed.dropFirst(2)) : trimmed
        if hexBody.filter({ !$0.isWhitespace }).count >= 4, !hexBody.isEmpty,
           hexBody.allSatisfy({ isHexDigit($0) || $0.isWhitespace }),
           let out = try? hexDecode(trimmed), isReadable(out), englishLikeness(out) > 0.05 {
            candidates.append(CipherCandidate(cipher: String(localized: "Hex"), cipherId: .hex,
                                              detail: "", output: out, score: 0.88))
        }

        if bare.count >= 4, bare.count % 4 == 0,
           trimmed.allSatisfy({ isAsciiAlphanumeric($0) || "+/=".contains($0) || $0.isWhitespace }),
           let out = try? base64Decode(trimmed), isReadable(out), englishLikeness(out) > 0.05 {
            candidates.append(CipherCandidate(cipher: String(localized: "Base64"), cipherId: .base64,
                                              detail: "", output: out, score: 0.85))
        }

        var cleanedB32 = bare.uppercased()
        while cleanedB32.hasSuffix("=") { cleanedB32.removeLast() }
        if cleanedB32.count >= 8,
           cleanedB32.allSatisfy({ ("A"..."Z").contains($0) || ("2"..."7").contains($0) }),
           let out = try? base32Decode(trimmed), isReadable(out), englishLikeness(out) > 0.05 {
            candidates.append(CipherCandidate(cipher: String(localized: "Base32"), cipherId: .base32,
                                              detail: "", output: out, score: 0.82))
        }

        if trimmed.allSatisfy({ "ABab".contains($0) || $0.isWhitespace }),
           bare.count >= 10 {
            let out = baconDecode(trimmed)
            if englishLikeness(out) > 0.1 {
                candidates.append(CipherCandidate(cipher: String(localized: "Bacon's cipher"), cipherId: .bacon,
                                                  detail: "", output: out, score: 0.78))
            }
        }

        if trimmed.contains(where: { ("0"..."9").contains($0) }),
           trimmed.allSatisfy({ ("0"..."9").contains($0) || $0.isWhitespace || "-/,.".contains($0) }) {
            let out = a1z26Decode(trimmed)
            if !out.isEmpty, englishLikeness(out) > 0.1 {
                candidates.append(CipherCandidate(cipher: String(localized: "A1Z26"), cipherId: .a1z26,
                                                  detail: "", output: out, score: 0.75))
            }
        }

        if trimmed.contains(where: { $0.isASCII && $0.isLetter }) {
            candidates += letterCiphers(trimmed, probe: String(trimmed.prefix(probeLimit)))
        }

        var best: [String: CipherCandidate] = [:]
        var order: [String] = []
        for candidate in candidates {
            if let previous = best[candidate.output] {
                if candidate.score > previous.score { best[candidate.output] = candidate }
            } else {
                best[candidate.output] = candidate
                order.append(candidate.output)
            }
        }
        return order.compactMap { best[$0] }
            .enumerated()
            .sorted { $0.element.score == $1.element.score ? $0.offset < $1.offset
                                                          : $0.element.score > $1.element.score }
            .prefix(8)
            .map(\.element)
    }

    /// Every substitution is scored on `probe` and only re-run over the whole
    /// text once it is kept, so the ~330 trial decodes stay bounded.
    private static func letterCiphers(_ trimmed: String, probe: String) -> [CipherCandidate] {
        var candidates: [CipherCandidate] = []

        var caesarTries: [(shift: Int, score: Double)] = []
        for s in 1..<26 {
            caesarTries.append((s, englishLikeness(caesarShift(probe, -s))))
        }
        caesarTries.sort { $0.score == $1.score ? $0.shift < $1.shift : $0.score > $1.score }
        for attempt in caesarTries.prefix(3) where attempt.score > 0.2 {
            let isRot13 = attempt.shift == 13
            var params = CipherParams()
            params.caesarShift = attempt.shift
            candidates.append(CipherCandidate(
                cipher: isRot13 ? String(localized: "ROT13") : String(localized: "Caesar (shift \(attempt.shift))"),
                cipherId: isRot13 ? .rot13 : .caesar,
                detail: "", output: caesarShift(trimmed, -attempt.shift), score: attempt.score,
                params: isRot13 ? nil : params))
        }

        let atbashScore = englishLikeness(atbash(probe))
        if atbashScore > 0.2 {
            candidates.append(CipherCandidate(cipher: String(localized: "Atbash"), cipherId: .atbash,
                                              detail: "", output: atbash(trimmed),
                                              score: atbashScore))
        }

        let rottedScore = englishLikeness(rot47(probe))
        if rottedScore > 0.25 {
            candidates.append(CipherCandidate(cipher: String(localized: "ROT47"), cipherId: .rot47,
                                              detail: "", output: rot47(trimmed),
                                              score: rottedScore))
        }

        if let guess = guessVigenereKey(probe) {
            let score = englishLikeness(vigenere(probe, key: guess.key, encode: false))
            if score > 0.25 {
                let decoded = vigenere(trimmed, key: guess.key, encode: false)
                var params = CipherParams()
                params.vigenereKey = guess.key
                candidates.append(CipherCandidate(cipher: String(localized: "Vigenère"), cipherId: .vigenere,
                                                  detail: String(localized: "key: \(guess.key)"), output: decoded,
                                                  score: score * 0.95, params: params))
            }
        }

        var bestAffine: (a: Int, b: Int, score: Double)?
        for a in affineCoprimes where a != 1 {
            for b in 0..<26 {
                guard let out = try? affine(probe, a: a, b: b, encode: false) else { continue }
                let score = englishLikeness(out)
                if bestAffine == nil || score > bestAffine!.score {
                    bestAffine = (a, b, score)
                }
            }
        }
        if let bestAffine, bestAffine.score > 0.3,
           let output = try? affine(trimmed, a: bestAffine.a, b: bestAffine.b, encode: false) {
            var params = CipherParams()
            params.affineA = bestAffine.a
            params.affineB = bestAffine.b
            candidates.append(CipherCandidate(cipher: String(localized: "Affine"), cipherId: .affine,
                                              detail: "a=\(bestAffine.a), b=\(bestAffine.b)",
                                              output: output,
                                              score: bestAffine.score * 0.9, params: params))
        }

        var bestRail: (rails: Int, output: String, score: Double)?
        for r in 2...8 {
            let out = railFenceDecode(trimmed, rails: r)
            let score = englishLikeness(out)
            if bestRail == nil || score > bestRail!.score { bestRail = (r, out, score) }
        }
        if let bestRail, bestRail.score > 0.3 {
            var params = CipherParams()
            params.rails = bestRail.rails
            candidates.append(CipherCandidate(cipher: String(localized: "Rail fence"), cipherId: .railFence,
                                              detail: String(localized: "\(bestRail.rails) rails"),
                                              output: bestRail.output,
                                              score: bestRail.score * 0.85, params: params))
        }

        return candidates
    }

    /// Decoded bytes that are text: valid UTF-8 with no control characters but whitespace. Letters in random bytes
    /// otherwise scored above the real reading (the Caesar sample read as Base32).
    public static func isReadable(_ text: String) -> Bool {
        !text.unicodeScalars.contains { $0 == "\u{FFFD}" || ($0.properties.generalCategory == .control && !$0.properties.isWhitespace) }
    }

    private static func isHexDigit(_ char: Character) -> Bool {
        ("0"..."9").contains(char) || ("a"..."f").contains(char) || ("A"..."F").contains(char)
    }

    private static func isAsciiAlphanumeric(_ char: Character) -> Bool {
        ("0"..."9").contains(char) || ("a"..."z").contains(char) || ("A"..."Z").contains(char)
    }

    // MARK: - Tokenising helpers

    private struct Chunk {
        public let text: String
        public let isWhitespaceRun: Bool
    }

    // whitespace runs and other runs
    private static func chunks(_ text: String) -> [Chunk] {
        var out: [Chunk] = []
        var current = ""
        var isSpace: Bool?
        for char in text {
            if isSpace != char.isWhitespace, !current.isEmpty {
                out.append(Chunk(text: current, isWhitespaceRun: isSpace == true))
                current = ""
            }
            isSpace = char.isWhitespace
            current.append(char)
        }
        if !current.isEmpty { out.append(Chunk(text: current, isWhitespaceRun: isSpace == true)) }
        return out
    }

    #if DEBUG
    public static func selfCheck() {
        assert(caesarShift("abc", 3) == "def")
        assert(caesarShift("AOL", -7) == "THE")
        assert(atbash("abc") == "zyx")
        assert(rot47(rot47("Hi!")) == "Hi!")
        assert(vigenere("attack", key: "lemon", encode: true) == "lxfopv")
        assert(vigenere("lxfopv", key: "lemon", encode: false) == "attack")
        let affineRound = (try? affine("test", a: 5, b: 8, encode: true))
            .flatMap { try? affine($0, a: 5, b: 8, encode: false) }
        assert(affineRound == "test")
        assert((try? affine("x", a: 2, b: 0, encode: false)) == nil)
        assert(modInverse(5, 26) == 21)
        assert(modInverse(2, 26) == nil)
        assert(morseDecode(".... . .-.. .-.. --- / .-- --- .-. .-.. -..") == "HELLO WORLD")
        assert(a1z26Decode("8-5-12-12-15") == "HELLO")
        assert(baconDecode(baconEncode("HI")) == "HI")
        assert(railFenceDecode(railFenceEncode("WEAREDISCOVERED", rails: 3), rails: 3) == "WEAREDISCOVERED")
        assert((try? base64Decode(base64Encode("crow"))) == "crow")
        assert((try? base32Decode(base32Encode("crow"))) == "crow")
        assert((try? hexDecode(hexEncode("crow"))) == "crow")
        assert((try? binaryDecode(binaryEncode("crow"))) == "crow")
        assert(bacon["A"] == "AAAAA" && bacon["Z"] == "BBAAB")
        assert(classifyAndDecode(samples[1].text).first?.cipherId == .rot13)
        assert(classifyAndDecode("").isEmpty)
        assert(classifyAndDecode(samples[0].text).first?.cipherId == .caesar)
        assert(classifyAndDecode(samples[5].text).first?.cipherId == .base64)
        // a long text is scored on a prefix but decoded whole
        let long = String(repeating: samples[1].text + " ", count: 40)
            .trimmingCharacters(in: .whitespaces)
        let rotted = classifyAndDecode(long).first { $0.cipherId == .rot13 }
        assert(rotted?.output.count == long.count)
        // more rails than characters cannot allocate per rail
        assert(railFenceEncode("hi", rails: 900_000) == "hi")
        assert(railFenceDecode("hi", rails: 900_000) == "hi")
    }
    #endif
}
