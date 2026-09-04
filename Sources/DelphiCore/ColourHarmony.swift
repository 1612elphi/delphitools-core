import Foundation

public enum HarmonyMode: String, CaseIterable, Identifiable, Sendable {
    case complementary, analogous, triadic, splitComplementary, tetradic, monochromatic
    case doubleComplementary, compound, pentadic, analogousAccent, goldenRatio, nearComplementary

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .complementary: "Complementary"
        case .analogous: "Analogous"
        case .triadic: "Triadic"
        case .splitComplementary: "Split-Comp."
        case .tetradic: "Tetradic"
        case .monochromatic: "Monochromatic"
        case .doubleComplementary: "Double-Comp."
        case .compound: "Compound"
        case .pentadic: "Pentadic"
        case .analogousAccent: "Analogous Accent"
        case .goldenRatio: "Golden Ratio"
        case .nearComplementary: "Near-Comp."
        }
    }

    var angles: [Double] {
        switch self {
        case .complementary: [0, 180]
        case .analogous: [-30, 0, 30]
        case .triadic: [0, 120, 240]
        case .splitComplementary: [0, 150, 210]
        case .tetradic: [0, 90, 180, 270]
        case .monochromatic: [0]
        case .doubleComplementary: [0, 60, 180, 240]
        case .compound: [0, 30, 180, 210]
        case .pentadic: [0, 72, 144, 216, 288]
        case .analogousAccent: [-30, 0, 30, 180]
        case .goldenRatio: [0, 137.5, 275]
        case .nearComplementary: [0, 165]
        }
    }
}

extension DelphiColour {
    /// OKLCH hue rotation by `mode.angles`; monochromatic steps lightness instead.
    public func harmony(_ mode: HarmonyMode) -> [DelphiColour] {
        let base = oklch
        if mode == .monochromatic {
            return [0.85, 0.70, base.l, 0.40, 0.25].map { l in
                DelphiColour.fromOKLCH(l: l, c: l > 0.6 ? base.c * 0.7 : base.c, h: base.h)
            }
        }
        return mode.angles.map { DelphiColour.fromOKLCH(l: base.l, c: base.c, h: base.h + $0) }
    }
}
