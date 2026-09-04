import Foundation

public struct WCAGLevel: Identifiable, Sendable {
    public let name: String
    public let ratio: Double

    public var id: String { name }

    public static let aa = 4.5
    public static let aaa = 7.0

    public static let all = [
        WCAGLevel(name: "AA normal", ratio: aa),
        WCAGLevel(name: "AA large", ratio: 3),
        WCAGLevel(name: "AAA normal", ratio: aaa),
        WCAGLevel(name: "AAA large", ratio: aa),
    ]
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
