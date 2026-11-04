import Foundation

public struct WCAGLevel: Identifiable, Sendable {
    public let name: String
    public let ratio: Double

    public var id: String { name }

    public static let aa = 4.5
    public static let aaLarge = 3.0
    public static let aaa = 7.0

    public static let all = [
        WCAGLevel(name: "AA normal", ratio: aa),
        WCAGLevel(name: "AA large", ratio: aaLarge),
        WCAGLevel(name: "AAA normal", ratio: aaa),
        WCAGLevel(name: "AAA large", ratio: aa),
    ]

    /// "AAA", "AA", "AA large" or "Fail".
    public static func grade(for ratio: Double) -> String {
        ratio >= aaa ? "AAA" : ratio >= aa ? "AA" : ratio >= aaLarge ? "AA large" : "Fail"
    }
}

extension DelphiColour {
    /// Steps HSL lightness until the ratio reaches `target`; returns `self` when no step does.
    public func adjusted(toContrast target: Double, against background: DelphiColour) -> DelphiColour {
        let start = hsl
        let backgroundLuminance = background.relativeLuminance
        let directions: [Double] = backgroundLuminance > 0.5 ? [-1, 1] : [1, -1]
        for direction in directions {
            for l in stride(from: start.l, through: direction > 0 ? 100 : 0, by: direction) {
                let candidate = DelphiColour.fromHSL(h: start.h, s: start.s, l: l)
                let luminance = candidate.relativeLuminance
                let ratio = (max(luminance, backgroundLuminance) + 0.05) / (min(luminance, backgroundLuminance) + 0.05)
                if ratio >= target { return candidate }
            }
        }
        return self
    }
}

/// WCAG 2.2 contrast levels (1.4.3, 1.4.6, 1.4.11) and the ratio as text.
public enum ContrastRatio: Sendable {
    /// AA for large text and for controls.
    public static let aaLarge = 3.0
    /// AA for normal text, AAA for large text.
    public static let aa = 4.5
    /// AAA for normal text.
    public static let aaa = 7.0

    /// Not rounded up: 4.499 shows 4.49, which fails 4.5 as the lamps do. No trailing zeros.
    public static func figure(_ ratio: Double) -> String {
        var text = String(format: "%.2f", (ratio * 100 + 1e-9).rounded(.down) / 100)
        while text.contains("."), text.hasSuffix("0") || text.hasSuffix(".") { text.removeLast() }
        return text
    }

    #if DEBUG
    public static func selfCheck() {
        assert(figure(4.499) == "4.49")
        assert(figure(4.5) == "4.5")
        assert(figure(21) == "21")
        assert(figure(7.001) == "7")
        // text matches lamp threshold
        assert((figure(4.4999) == "4.5") == (4.4999 >= aa))
        let white = DelphiColour(r: 1, g: 1, b: 1)
        assert(figure(DelphiColour.contrastRatio(white, DelphiColour(r: 0, g: 0, b: 0))) == "21")
        let grey = DelphiColour.fromHex("777777")!
        let fixed = grey.adjusted(toContrast: aa, against: white)
        assert(DelphiColour.contrastRatio(fixed, white) >= aa && fixed.hsl.l < grey.hsl.l)
    }
    #endif
}
