import Foundation

/// Bytes regrouped into the characters of an encoding. A group is the bits of a whole number of bytes and of characters
/// (Base64: three bytes, four sixes); the input's units are bracketed over the bits, the output's under them.
public enum BitRegroup: Sendable {
    public enum Slot: Equatable, Sendable {
        case one, zero
        /// A zero added to fill the last character, or a bit dropped because it makes no whole byte.
        case pad
        /// A place the input does not reach: the room `=` padding stands for.
        case absent
    }

    public struct Unit: Equatable, Sendable {
        public var label: String
        public var span: Int
        public var faint = false
    }

    public struct Group: Equatable, Sendable {
        public var slots: [Slot]
        public var top: [Unit]
        public var bottom: [Unit]
    }

    public struct Code: Sendable {
        public let bits: Int
        public let alphabet: [Character]
        public let bytesPerGroup: Int
        public let padding: Character?
        /// Value of each ASCII character, -1 for none.
        private let table: [Int]

        public init(bits: Int, alphabet: [Character], bytesPerGroup: Int, padding: Character?) {
            (self.bits, self.alphabet, self.bytesPerGroup, self.padding) = (bits, alphabet, bytesPerGroup, padding)
            var table = Array(repeating: -1, count: 128)
            for (value, character) in alphabet.enumerated() {
                for form in [character, Character(character.lowercased()), Character(character.uppercased())] {
                    // base64 is case-sensitive
                    if let ascii = form.asciiValue, bits != 6 || form == character { table[Int(ascii)] = value }
                }
            }
            if bits == 6 {
                table[Int(Character("-").asciiValue!)] = 62
                table[Int(Character("_").asciiValue!)] = 63
            }
            self.table = table
        }

        public var charsPerGroup: Int { bytesPerGroup * 8 / bits }

        public static let base64 = Code(bits: 6, alphabet: Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"), bytesPerGroup: 3, padding: "=")
        public static let base32 = Code(bits: 5, alphabet: Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"), bytesPerGroup: 5, padding: "=")
        public static let hex = Code(bits: 4, alphabet: Array("0123456789abcdef"), bytesPerGroup: 1, padding: nil)
        public static let binary = Code(bits: 1, alphabet: ["0", "1"], bytesPerGroup: 1, padding: nil)

        /// The character's value; Base64 also reads the URL-safe `-` and `_`, hex and Base32 either case.
        public func value(of character: Character) -> Int? {
            guard let ascii = character.asciiValue, table[Int(ascii)] >= 0 else { return nil }
            return table[Int(ascii)]
        }
    }

    /// Byte labels: a character over its first byte and nothing over the rest of it, a visible sign for space, tab
    /// and newline, the hex of anything else.
    public static func labels(_ bytes: [UInt8]) -> [String] {
        var out = Array(repeating: "", count: bytes.count)
        var i = 0
        while i < bytes.count {
            let byte = bytes[i]
            let length = byte < 0x80 ? 1 : byte >= 0xF8 ? 0 : byte >= 0xF0 ? 4 : byte >= 0xE0 ? 3 : byte >= 0xC0 ? 2 : 0
            if length > 1, i + length <= bytes.count, let text = String(bytes: bytes[i..<i + length], encoding: .utf8) {
                out[i] = text
                i += length
                continue
            }
            out[i] = switch byte {
            case 0x20: "\u{2423}"
            case 0x0A: "\u{21B5}"
            case 0x09: "\u{21E5}"
            case 0x21...0x7E: String(UnicodeScalar(byte))
            default: String(format: "%02X", byte)
            }
            i += 1
        }
        return out
    }

    /// Labels for `range` of `bytes`, read from three bytes before it so a character cut by the range labels as in the whole.
    public static func labels(_ bytes: [UInt8], in range: Range<Int>) -> [String] {
        let from = max(0, range.lowerBound - 3), to = min(bytes.count, range.upperBound + 3)
        return Array(labels(Array(bytes[from..<to]))[(range.lowerBound - from)..<(range.upperBound - from)])
    }

    private static func slots(_ byte: UInt8) -> [Slot] {
        (0..<8).map { byte >> (7 - $0) & 1 == 1 ? .one : .zero }
    }

    /// Binary's one-bit characters read as one label per byte.
    private static func merged(_ units: [Unit], code: Code) -> [Unit] {
        guard code.bits == 1, !units.isEmpty else { return units }
        return [Unit(label: units.map(\.label).joined(), span: units.reduce(0) { $0 + $1.span })]
    }

    /// An input read once; its groups are built only for the range asked for, so a long input costs no more than its tail.
    public struct Reading {
        public let code: Code
        public let count: Int
        public let groups: (Range<Int>) -> [Group]

        public var all: [Group] { groups(0..<count) }
    }

    public static func encoding(_ bytes: [UInt8], code: Code) -> Reading {
        let total = code.bytesPerGroup * 8
        return Reading(code: code, count: (bytes.count + code.bytesPerGroup - 1) / code.bytesPerGroup) { range in
            let first = min(bytes.count, range.lowerBound * code.bytesPerGroup)
            let last = min(bytes.count, range.upperBound * code.bytesPerGroup)
            let names = labels(bytes, in: first..<last)
            return stride(from: first, to: last, by: code.bytesPerGroup).map { start in
                let chunk = Array(bytes[start..<min(start + code.bytesPerGroup, bytes.count)])
                let real = chunk.count * 8
                let used = (real + code.bits - 1) / code.bits * code.bits
                let slots = chunk.flatMap(slots) + Array(repeating: Slot.pad, count: used - real) + Array(repeating: Slot.absent, count: total - used)
                let top = (0..<code.bytesPerGroup).map { i in
                    i < chunk.count ? Unit(label: names[start - first + i], span: 8) : Unit(label: "", span: 8, faint: true)
                }
                let bottom = (0..<code.charsPerGroup).map { k -> Unit in
                    let from = k * code.bits
                    guard from < used else { return Unit(label: code.padding.map(String.init) ?? "", span: code.bits, faint: true) }
                    let value = (0..<code.bits).reduce(0) { $0 << 1 | (slots[from + $1] == .one ? 1 : 0) }
                    return Unit(label: String(code.alphabet[value]), span: code.bits)
                }
                return Group(slots: slots, top: top, bottom: merged(bottom, code: code))
            }
        }
    }

    /// Encoded text, whitespace already removed. Reading stops at the first character the code does not have.
    public static func decoding(_ characters: [Character], code: Code) -> Reading {
        var values: [Int] = []
        var padding = 0
        for character in characters {
            if character == code.padding {
                padding += 1
            } else if padding == 0, let value = code.value(of: character) {
                values.append(value)
            } else {
                break
            }
        }
        let realBits = values.count * code.bits
        var bytes: [UInt8] = []
        bytes.reserveCapacity(realBits / 8)
        var accumulator = 0
        var filled = 0
        for value in values {
            accumulator = accumulator << code.bits | value
            filled += code.bits
            if filled >= 8 {
                bytes.append(UInt8(accumulator >> (filled - 8) & 0xFF))
                filled -= 8
                accumulator &= (1 << filled) - 1
            }
        }
        let kept = bytes.count * 8
        let perGroup = code.charsPerGroup
        let length = values.count + padding
        return Reading(code: code, count: (length + perGroup - 1) / perGroup) { range in
            let firstByte = min(bytes.count, range.lowerBound * code.bytesPerGroup)
            let names = labels(bytes, in: firstByte..<min(bytes.count, range.upperBound * code.bytesPerGroup))
            return stride(from: range.lowerBound * perGroup, to: min(length, range.upperBound * perGroup), by: perGroup).map { start in
                var slots: [Slot] = []
                var top: [Unit] = []
                for index in start..<start + perGroup {
                    guard index < values.count else {
                        slots += Array(repeating: .absent, count: code.bits)
                        top.append(Unit(label: index < length ? code.padding.map(String.init) ?? "" : "", span: code.bits, faint: true))
                        continue
                    }
                    let value = values[index]
                    let bitBase = index * code.bits
                    slots += (0..<code.bits).map { bit in
                        bitBase + bit >= kept && bitBase + bit < realBits ? .pad : value >> (code.bits - 1 - bit) & 1 == 1 ? .one : .zero
                    }
                    top.append(Unit(label: String(characters[index]), span: code.bits))
                }
                let byte = start / perGroup * code.bytesPerGroup
                let bottom = (0..<code.bytesPerGroup).map { j in
                    byte + j < bytes.count ? Unit(label: names[byte + j - firstByte], span: 8) : Unit(label: "", span: 8, faint: true)
                }
                return Group(slots: slots, top: merged(top, code: code), bottom: bottom)
            }
        }
    }

    /// One group of the code, all zeros, no labels: the strip's picture with no input.
    public static func ghost(_ code: Code) -> Group? {
        guard var group = encoding(Array(repeating: 0, count: code.bytesPerGroup), code: code).all.first else { return nil }
        group.top = group.top.map { Unit(label: "", span: $0.span) }
        group.bottom = group.bottom.map { Unit(label: "", span: $0.span) }
        return group
    }

    #if DEBUG
    public static func selfCheck() {
        func encode(_ bytes: [UInt8], code: Code) -> [Group] { encoding(bytes, code: code).all }
        func decode(_ characters: [Character], code: Code) -> [Group] { decoding(characters, code: code).all }
        let ma = encode(Array("Ma".utf8), code: .base64)
        assert(ma.count == 1 && ma[0].bottom.map(\.label) == ["T", "W", "E", "="])
        assert(ma[0].slots.filter { $0 == .pad }.count == 2 && ma[0].slots.filter { $0 == .absent }.count == 6)
        assert(ma[0].top.map(\.label) == ["M", "a", ""] && ma[0].top[2].faint)
        let back = decode(Array("TWE="), code: .base64)
        assert(back.count == 1 && back[0].bottom.map(\.label) == ["M", "a", ""] && back[0].slots.filter { $0 == .pad }.count == 2)
        // url-safe, unpadded
        assert(decode(Array("_w"), code: .base64)[0].bottom[0].label == "FF")
        assert(encode(Array("f".utf8), code: .base32)[0].bottom.map(\.label) == ["M", "Y", "=", "=", "=", "=", "=", "="])
        assert(encode([0x48], code: .hex)[0].bottom.map(\.label) == ["4", "8"])
        assert(encode([0x48], code: .binary)[0].bottom.map(\.label) == ["01001000"])
        assert(decode(Array("4A"), code: .hex)[0].bottom[0].label == "J")
        assert(labels(Array("é ".utf8)) == ["é", "", "\u{2423}"])
        // stops at foreign character
        assert(decode(Array("TW!E"), code: .base64)[0].top.filter { !$0.faint }.count == 2)
        assert(decode(Array("TWFu===="), code: .base64).count == 2)
        assert(Code.hex.value(of: "F") == 15 && Code.base32.value(of: "b") == 1 && Code.base64.value(of: "b") == 27 && Code.binary.value(of: "2") == nil)
        // range equals whole's tail
        let text = Array("a€😀b€é".utf8)
        let whole = encode(text, code: .base64), tail = encoding(text, code: .base64).groups(2..<whole.count)
        assert(tail == Array(whole[2...]))
        let coded = Array(Data(text).base64EncodedString())
        let decoded = decode(coded, code: .base64), decodedTail = decoding(coded, code: .base64).groups(1..<decoded.count)
        assert(decodedTail == Array(decoded[1...]) && decoded.map(\.bottom) == whole.map(\.top))
    }
    #endif
}
