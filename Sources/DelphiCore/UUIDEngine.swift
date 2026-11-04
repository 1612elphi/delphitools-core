import Foundation

public enum IdentifierKind: String, CaseIterable, Identifiable, Sendable {
    case uuid4
    case uuid7
    case nanoid

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .uuid4: String(localized: "UUID v4")
        case .uuid7: String(localized: "UUID v7")
        case .nanoid: String(localized: "Nano ID")
        }
    }
}

public struct IdentifierOptions: Sendable {
    public var uppercase = false
    public var stripHyphens = false

    public init(uppercase: Bool = false, stripHyphens: Bool = false) {
        self.uppercase = uppercase
        self.stripHyphens = stripHyphens
    }
}

public enum UUIDEngine {

    public static let nanoIDAlphabet = Array(
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-")

    public static let nanoIDLength = 21
    public static let countMin = 1
    public static let countMax = 100

    private static func randomBytes(_ count: Int) -> [UInt8] {
        (0..<max(0, count)).map { _ in UInt8.random(in: .min ... .max) }
    }

    private static func uuidString(_ bytes: [UInt8]) -> String {
        let hex = bytes.map { String(format: "%02x", $0) }
        return hex[0..<4].joined() + "-" + hex[4..<6].joined() + "-"
            + hex[6..<8].joined() + "-" + hex[8..<10].joined() + "-" + hex[10...].joined()
    }

    public static func uuid4() -> String {
        UUID().uuidString.lowercased()
    }

    public static func uuid7(milliseconds: UInt64 = UInt64(Date().timeIntervalSince1970 * 1000)) -> String {
        var bytes = randomBytes(16)
        for offset in 0..<6 {
            bytes[offset] = UInt8((milliseconds >> (8 * (5 - UInt64(offset)))) & 0xFF)
        }
        bytes[6] = (bytes[6] & 0x0F) | 0x70
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return uuidString(bytes)
    }

    public static func uuid7Milliseconds(_ uuid: String) -> UInt64? {
        UInt64(uuid.replacingOccurrences(of: "-", with: "").prefix(12), radix: 16)
    }

    // 64 avoids modulo bias
    public static func nanoID(length: Int = nanoIDLength) -> String {
        String(randomBytes(length).map { nanoIDAlphabet[Int($0) % 64] })
    }

    public static func clamp(count: Int) -> Int {
        min(countMax, max(countMin, count))
    }

    public static func clamp(count: Double) -> Int {
        count.isFinite ? clamp(count: Int(min(max(count, -1), Double(countMax)))) : countMin
    }

    public static func generate(_ kind: IdentifierKind) -> String {
        switch kind {
        case .uuid4: uuid4()
        case .uuid7: uuid7()
        case .nanoid: nanoID()
        }
    }

    public static func generate(_ kind: IdentifierKind, count: Int) -> [String] {
        (0..<clamp(count: count)).map { _ in generate(kind) }
    }

    public static func format(_ id: String, kind: IdentifierKind, options: IdentifierOptions) -> String {
        guard kind != .nanoid else { return id }
        let text = options.stripHyphens ? id.replacingOccurrences(of: "-", with: "") : id
        return options.uppercase ? text.uppercased() : text
    }

    #if DEBUG
    public static func selfCheck() {
        let v4 = uuid4()
        assert(v4.count == 36)
        assert(Array(v4)[14] == "4")
        assert("89ab".contains(Array(v4)[19]))

        let v7 = uuid7(milliseconds: 0x018F_1234_5678)
        assert(Array(v7)[14] == "7")
        assert("89ab".contains(Array(v7)[19]))
        assert(uuid7Milliseconds(v7) == 0x018F_1234_5678)

        assert(nanoID().count == nanoIDLength)
        assert(nanoID(length: 5).allSatisfy(nanoIDAlphabet.contains))

        assert(clamp(count: 0) == 1 && clamp(count: 999) == 100)
        assert(clamp(count: Double.nan) == 1 && clamp(count: 1e300) == 100 && clamp(count: 7.9) == 7)
        assert(nanoID(length: -1).isEmpty)
        assert(uuid7() <= uuid7(milliseconds: UInt64(Date().timeIntervalSince1970 * 1000) + 1000))
        assert(generate(.uuid4, count: 3).count == 3)
        assert(Set(generate(.uuid4, count: 20)).count == 20)

        let options = IdentifierOptions(uppercase: true, stripHyphens: true)
        assert(format(v4, kind: .uuid4, options: options) == v4.replacingOccurrences(
            of: "-", with: "").uppercased())
        assert(format("abc", kind: .nanoid, options: options) == "abc")
    }
    #endif
}
