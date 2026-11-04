import Foundation

public enum BaseNumber: Sendable {
    public enum Radix: Int, CaseIterable, Sendable {
        case decimal, hex, binary, octal

        public var radix: Int { [10, 16, 2, 8][rawValue] }
        public var prefix: String { ["", "0x", "0b", "0o"][rawValue] }
        public var short: String { ["DEC", "HEX", "BIN", "OCT"][rawValue] }
        public var placeholder: String { ["255", "FF", "11111111", "377"][rawValue] }
        public var highestDigit: String { String(radix - 1, radix: radix, uppercase: true) }

        public var name: String {
            switch self {
            case .decimal: String(localized: "Decimal")
            case .hex: String(localized: "Hexadecimal")
            case .binary: String(localized: "Binary")
            case .octal: String(localized: "Octal")
            }
        }
    }

    public enum Reading: Equatable, Sendable {
        case empty
        case value(UInt64)
        case invalid(Character)
        case tooLarge

        public var value: UInt64? {
            if case .value(let value) = self { value } else { nil }
        }
    }

    public enum Operation: Int, CaseIterable, Sendable {
        case and, or, xor, not, left, right

        public var title: String { ["AND", "OR", "XOR", "NOT", "<<", ">>"][rawValue] }
        public var takesOperand: Bool { rawValue <= 2 }
        public var takesShift: Bool { self == .left || self == .right }
    }

    /// Reads a number typed in `radix`. A 0x, 0b or 0o prefix picks its own base (hex keeps 0b as digits); underscores,
    /// spaces and apostrophes between digits are separators.
    public static func read(_ text: String, in radix: Radix) -> Reading {
        var body = text.lowercased().filter { $0 != "_" && $0 != "'" && !$0.isWhitespace }
        let detected = base(of: body, in: radix)
        if body.hasPrefix(detected.prefix) { body.removeFirst(detected.prefix.count) }
        guard !body.isEmpty else { return .empty }
        if let foreign = body.first(where: { Int(String($0), radix: detected.radix) == nil }) { return .invalid(foreign) }
        guard let value = UInt64(body, radix: detected.radix) else { return .tooLarge }
        return .value(value)
    }

    /// The base the text is read in: its prefix's, else `radix`.
    public static func base(of text: String, in radix: Radix) -> Radix {
        let body = text.lowercased().filter { !$0.isWhitespace }
        return [Radix.hex, .binary, .octal].first { body.hasPrefix($0.prefix) && (radix != .hex || $0 == .hex) } ?? radix
    }

    public static func format(_ value: UInt64, in radix: Radix, prefixed: Bool = false) -> String {
        (prefixed ? radix.prefix : "") + String(value, radix: radix.radix, uppercase: true)
    }

    /// The smallest of 8, 16, 32 and 64 bits that holds the value.
    public static func word(fitting value: UInt64) -> Int {
        let bits = UInt64.bitWidth - value.leadingZeroBitCount
        return [8, 16, 32, 64].first { bits <= $0 } ?? 64
    }

    /// The operation within a word of `word` bits; nil while an operation still waits for B.
    public static func apply(_ operation: Operation, a: UInt64, b: UInt64?, shift: Int, word: Int) -> UInt64? {
        let mask = word >= 64 ? UInt64.max : (UInt64(1) << UInt64(word)) - 1
        switch operation {
        case .and: return b.map { a & $0 & mask }
        case .or: return b.map { (a | $0) & mask }
        case .xor: return b.map { (a ^ $0) & mask }
        case .not: return ~a & mask
        case .left: return shift >= word ? 0 : (a << UInt64(shift)) & mask
        case .right: return shift >= 64 ? 0 : a >> UInt64(shift)
        }
    }

    #if DEBUG
    public static func selfCheck() {
        assert(read("0xff", in: .decimal) == .value(255) && read("ff", in: .hex) == .value(255))
        assert(read("0b12", in: .hex) == .value(0xB12) && read("0b101", in: .decimal) == .value(5))
        assert(read("1_000 000", in: .decimal) == .value(1_000_000) && read("0o17", in: .binary) == .value(15))
        assert(read("9", in: .octal) == .invalid("9") && read("0x", in: .decimal) == .empty)
        assert(read("18446744073709551616", in: .decimal) == .tooLarge)
        assert(format(255, in: .hex, prefixed: true) == "0xFF" && format(5, in: .binary) == "101")
        assert(word(fitting: 255) == 8 && word(fitting: 256) == 16 && word(fitting: .max) == 64)
        assert(Radix.allCases.map(\.highestDigit) == ["9", "F", "1", "7"])
        assert(apply(.not, a: 0, b: nil, shift: 0, word: 8) == 255 && apply(.left, a: 0x80, b: nil, shift: 1, word: 8) == 0)
        assert(apply(.and, a: 12, b: nil, shift: 0, word: 8) == nil && apply(.xor, a: 12, b: 10, shift: 0, word: 8) == 6)
        assert(apply(.not, a: 0, b: nil, shift: 0, word: 64) == .max)
    }
    #endif
}
