import CryptoKit
import Foundation

public enum EncoderEngine: Sendable {
    public enum Algorithm: Int, CaseIterable, Sendable {
        case md5, sha1, sha256, sha512

        public var name: String { ["MD5", "SHA-1", "SHA-256", "SHA-512"][rawValue] }
        public var bits: Int { [128, 160, 256, 512][rawValue] }
    }

    public enum Failure: Error, Sendable {
        case base64, escape

        public var text: String {
            switch self {
            case .base64: String(localized: "Invalid Base64.")
            case .escape: String(localized: "Invalid escape")
            }
        }
    }

    /// `encodeURIComponent`'s unreserved set: everything else is escaped.
    private static let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.!~*'()")

    /// The characters of a Base64 text without whitespace.
    public static func base64Characters(_ text: String) -> [Character] {
        text.filter { !$0.isWhitespace }.map { $0 }
    }

    /// Accepts missing padding and the URL-safe alphabet.
    public static func base64Decode(_ text: String) -> Result<String, Failure> {
        let standard = String(base64Characters(text)).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        guard !standard.isEmpty else { return .success("") }
        guard let decoded = try? CipherEngine.base64Decode(standard) else { return .failure(.base64) }
        return .success(decoded)
    }

    public static func urlEncode(_ text: String) -> String {
        text.addingPercentEncoding(withAllowedCharacters: unreserved) ?? text
    }

    public static func urlDecode(_ text: String) -> Result<String, Failure> {
        guard !text.isEmpty else { return .success("") }
        guard let decoded = text.removingPercentEncoding else { return .failure(.escape) }
        return .success(decoded)
    }

    public static func urlEncodePairs(_ text: String) -> [SymbolPair] {
        text.map { character in
            if character.isNewline { return .newline }
            let escaped = urlEncode(String(character))
            let same = escaped == String(character)
            return SymbolPair(top: .text(character == " " ? "\u{2423}" : String(character)), bottom: .text(escaped), changes: !same)
        }
    }

    /// Runs of escapes read as the characters they spell; a run that is not UTF-8 reads as the replacement character.
    public static func urlDecodePairs(_ text: String) -> [SymbolPair] {
        let characters = Array(text)
        var pairs: [SymbolPair] = []
        var i = 0
        func byte(at index: Int) -> UInt8? {
            guard index + 2 < characters.count, characters[index] == "%" else { return nil }
            return UInt8(String(characters[index + 1...index + 2]), radix: 16)
        }
        while i < characters.count {
            guard byte(at: i) != nil else {
                let character = characters[i]
                pairs.append(character.isNewline ? .newline : .init(top: .text(String(character)), bottom: .text(String(character)), changes: false))
                i += 1
                continue
            }
            var run: [UInt8] = []
            while let next = byte(at: i + run.count * 3) { run.append(next) }
            let labels = BitRegroup.labels(run)
            var start = 0
            while start < run.count {
                var end = start + 1
                while end < run.count, labels[end].isEmpty { end += 1 }
                let escapes = run[start..<end].map { String(format: "%%%02X", $0) }.joined()
                let spelled = String(bytes: run[start..<end], encoding: .utf8) ?? "\u{FFFD}"
                pairs.append(.init(top: .text(escapes), bottom: .text(spelled == " " ? "\u{2423}" : spelled)))
                start = end
            }
            i += run.count * 3
        }
        return pairs
    }

    /// Every digest of the text's UTF-8 bytes, exactly as typed.
    public static func digests(_ text: String) -> [Algorithm: [UInt8]] {
        let data = Data(text.utf8)
        return [
            .md5: Array(Insecure.MD5.hash(data: data)),
            .sha1: Array(Insecure.SHA1.hash(data: data)),
            .sha256: Array(SHA256.hash(data: data)),
            .sha512: Array(SHA512.hash(data: data)),
        ]
    }

    public static func hex(_ bytes: [UInt8]) -> String {
        bytes.map { String(format: "%02x", $0) }.joined()
    }

    #if DEBUG
    public static func selfCheck() {
        assert(urlEncode("a b€&") == "a%20b%E2%82%AC%26")
        assert((try? urlDecode("a%20b%E2%82%AC").get()) == "a b€")
        assert((try? urlDecode("100%").get()) == nil)
        let decoded = urlDecodePairs("x%E2%82%ACy")
        assert(decoded.count == 3 && decoded[1].top == .text("%E2%82%AC") && decoded[1].bottom == .text("€"))
        assert(urlEncodePairs("a€").map(\.changes) == [false, true])
        assert((try? base64Decode("TWFu").get()) == "Man" && (try? base64Decode("TWE").get()) == "Ma")
        assert((try? base64Decode("_-8").get()) == String(decoding: [0xFF, 0xEF], as: UTF8.self))
        if case .success = base64Decode("T") { assertionFailure() }
        let abc = digests("abc")
        assert(hex(abc[.sha256]!) == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        assert(hex(abc[.md5]!) == "900150983cd24fb0d6963f7d28e17f72")
    }
    #endif
}
