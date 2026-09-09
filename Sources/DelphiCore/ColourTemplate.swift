import Foundation

/// `%[token]` substitution. Unknown tokens stay as written.
public enum ColourTemplate {
    // one conversion per render
    final class Values {
        let colour: DelphiColour
        lazy var rgb = colour.rgb
        lazy var hsb = colour.hsb
        lazy var hsl = colour.hsl
        lazy var cmyk = colour.cmyk
        lazy var lab = colour.lab
        lazy var lch = colour.lch
        lazy var oklab = colour.oklab
        lazy var oklch = colour.oklch
        lazy var p3 = colour.displayP3
        lazy var hex = colour.hexNoHash

        init(_ colour: DelphiColour) {
            self.colour = colour
        }
    }

    public struct Variable: Identifiable, Sendable {
        public let token: String
        public let label: String
        let value: @Sendable (Values) -> String

        public var id: String { token }
        public var placeholder: String { "%[\(token)]" }
    }

    public struct Group: Identifiable, Sendable {
        public let name: String
        public let variables: [Variable]

        public var id: String { name }
    }

    public static let groups: [Group] = [
        Group(name: "RGB", variables: [
            v("r", "R") { f3($0.colour.r) }, v("g", "G") { f3($0.colour.g) }, v("b", "B") { f3($0.colour.b) },
            v("r255", "R255") { "\($0.rgb.r)" }, v("g255", "G255") { "\($0.rgb.g)" }, v("b255", "B255") { "\($0.rgb.b)" },
        ]),
        Group(name: "HSB", variables: [
            v("hsb_h", "H") { f3($0.hsb.h / 360) }, v("hsb_s", "S") { f3($0.hsb.s) }, v("hsb_b", "B") { f3($0.hsb.b) },
            v("hsb_h360", "H360") { f0($0.hsb.h) }, v("hsb_s100", "S100") { f0($0.hsb.s * 100) }, v("hsb_b100", "B100") { f0($0.hsb.b * 100) },
        ]),
        Group(name: "HSL", variables: [
            v("hsl_h", "H") { f3($0.hsl.h / 360) }, v("hsl_s", "S") { f3($0.hsl.s / 100) }, v("hsl_l", "L") { f3($0.hsl.l / 100) },
            v("hsl_h360", "H360") { f0($0.hsl.h) }, v("hsl_s100", "S100") { f0($0.hsl.s) }, v("hsl_l100", "L100") { f0($0.hsl.l) },
        ]),
        Group(name: "CMYK", variables: [
            v("c", "C") { f3($0.cmyk.c) }, v("m", "M") { f3($0.cmyk.m) }, v("y", "Y") { f3($0.cmyk.y) }, v("k", "K") { f3($0.cmyk.k) },
            v("c100", "C100") { f0($0.cmyk.c * 100) }, v("m100", "M100") { f0($0.cmyk.m * 100) },
            v("y100", "Y100") { f0($0.cmyk.y * 100) }, v("k100", "K100") { f0($0.cmyk.k * 100) },
        ]),
        Group(name: "HEX", variables: [
            v("hex", "Hex") { "#" + $0.hex }, v("hex_raw", "Raw") { $0.hex },
            v("hexa", "Hexa") { $0.colour.hexa }, v("hexa_raw", "Hexa raw") { String($0.colour.hexa.dropFirst()) },
            v("hex_r", "R") { String($0.hex.prefix(2)) }, v("hex_g", "G") { String($0.hex.dropFirst(2).prefix(2)) },
            v("hex_b", "B") { String($0.hex.suffix(2)) }, v("hex_a", "A") { String(format: "%02X", $0.colour.alpha255) },
        ]),
        Group(name: "Alpha", variables: [
            v("alpha", "Alpha") { g($0.colour.a) }, v("alpha100", "Alpha 100") { f0(clamp01($0.colour.a) * 100) },
            v("alpha255", "Alpha 255") { "\($0.colour.alpha255)" },
        ]),
        Group(name: "LAB", variables: [
            v("lab_l", "L") { f1($0.lab.l) }, v("lab_a", "a") { f1($0.lab.a) }, v("lab_b", "b") { f1($0.lab.b) },
            v("lch_l", "LCH L") { f1($0.lch.l) }, v("lch_c", "LCH C") { f1($0.lch.c) }, v("lch_h", "LCH H") { f1($0.lch.h) },
        ]),
        Group(name: "OKLab", variables: [
            v("oklab_l", "L") { f4($0.oklab.l) }, v("oklab_a", "a") { f4($0.oklab.a) }, v("oklab_b", "b") { f4($0.oklab.b) },
            v("oklch_l", "LCH L") { f4($0.oklch.l) }, v("oklch_c", "LCH C") { f4($0.oklch.c) }, v("oklch_h", "LCH H") { f1($0.oklch.h) },
        ]),
        Group(name: "P3", variables: [
            v("p3_r", "R") { f4($0.p3.r) }, v("p3_g", "G") { f4($0.p3.g) }, v("p3_b", "B") { f4($0.p3.b) },
        ]),
        Group(name: "Name", variables: [
            v("name", "Name") { $0.colour.colourName },
        ]),
    ]

    public static let variables: [String: Variable] = Dictionary(uniqueKeysWithValues: groups.flatMap(\.variables).map { ($0.token, $0) })

    public static func render(_ template: String, _ colour: DelphiColour) -> String {
        let values = Values(colour)
        var output = ""
        var rest = Substring(template)
        while let open = rest.range(of: "%[") {
            output += rest[..<open.lowerBound]
            let afterOpen = rest[open.upperBound...]
            guard let close = afterOpen.firstIndex(of: "]"), let variable = variables[String(afterOpen[..<close])] else {
                output += "%["
                rest = afterOpen
                continue
            }
            output += variable.value(values)
            rest = afterOpen[afterOpen.index(after: close)...]
        }
        return output + rest
    }

    private static func v(_ token: String, _ label: String, _ value: @escaping @Sendable (Values) -> String) -> Variable {
        Variable(token: token, label: label, value: value)
    }

    private static func f0(_ value: Double) -> String { String(format: "%.0f", value) }
    private static func f1(_ value: Double) -> String { String(format: "%.1f", value) }
    private static func f3(_ value: Double) -> String { String(format: "%.3f", clamp01(value)) }
    private static func f4(_ value: Double) -> String { String(format: "%.4f", value) }
    private static func g(_ alpha: Double) -> String { String(format: "%g", clamp01(alpha)) }
}

extension DelphiColour {
    public var cmyk: (c: Double, m: Double, y: Double, k: Double) {
        let r0 = clamp01(r), g0 = clamp01(g), b0 = clamp01(b)
        let k = 1 - max(r0, g0, b0)
        guard k < 1 else { return (0, 0, 0, 1) }
        return ((1 - r0 - k) / (1 - k), (1 - g0 - k) / (1 - k), (1 - b0 - k) / (1 - k), k)
    }

    // towards white, chroma fades
    public func tints(_ count: Int) -> [DelphiColour] {
        let base = oklch
        return (1...max(count, 1)).map { i in
            let k = Double(i) / Double(count + 1)
            return DelphiColour.fromOKLCH(l: base.l + (1 - base.l) * k, c: base.c * (1 - k), h: base.h)
        }
    }

    public func shades(_ count: Int) -> [DelphiColour] {
        let base = oklch
        return (1...max(count, 1)).map { i in
            let k = Double(i) / Double(count + 1)
            return DelphiColour.fromOKLCH(l: base.l * (1 - k), c: base.c * (1 - k * 0.5), h: base.h)
        }
    }
}
