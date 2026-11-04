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

    public var angles: [Double] {
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

/// A colour space the harmony wheel turns in: hue around, chroma or saturation out, lightness as the plane.
/// `l` and `r` are 0...1 of the space's own lightness and of `reach`; hue is in degrees.
public enum HarmonyWheelSpace: Int, CaseIterable, Sendable {
    case oklch, lch, hsl

    public var name: String {
        switch self {
        case .oklch: "OKLCH"
        case .lch: "LCH"
        case .hsl: "HSL"
        }
    }

    /// The radial channel at the plane's edge, in its own units: OKLCH chroma, CIE chroma (sRGB blue reaches 134),
    /// HSL saturation in percent.
    public var reach: Double {
        switch self {
        case .oklch: 0.33
        case .lch: 134
        case .hsl: 100
        }
    }

    /// Lightness at full scale, in its own units.
    public var lightnessScale: Double { self == .oklch ? 1 : 100 }

    public func colour(l: Double, r: Double, h: Double) -> DelphiColour {
        switch self {
        case .oklch: DelphiColour.fromOKLCH(l: l, c: r * reach, h: h)
        case .lch: DelphiColour.fromLCH(l: l * 100, c: r * reach, h: h)
        case .hsl: DelphiColour.fromHSL(h: h, s: min(max(r, 0), 1) * 100, l: min(max(l, 0), 1) * 100)
        }
    }

    public func parts(of colour: DelphiColour) -> (l: Double, r: Double, h: Double) {
        switch self {
        case .oklch:
            let lch = colour.oklch
            return (lch.l, lch.c / reach, lch.h)
        case .lch:
            let lch = colour.lch
            return (lch.l / 100, lch.c / reach, lch.h)
        case .hsl:
            let hsl = colour.hsl
            return (hsl.l / 100, hsl.s / 100, hsl.h)
        }
    }

    /// The largest `r` inside sRGB at lightness `l` and hue `h`.
    public func maxRadius(l: Double, h: Double) -> Double {
        switch self {
        case .oklch:
            return DelphiColour.maxChroma(lightness: l, hue: h) / reach
        case .hsl:
            return 1
        case .lch:
            // lost chroma means out-of-gamut
            var lo = 0.0, hi = 1.0
            for _ in 0..<22 {
                let mid = (lo + hi) / 2
                let colour = colour(l: l, r: mid, h: h)
                let inside = [colour.r, colour.g, colour.b].allSatisfy { $0 <= 1 + 1e-5 } && abs(colour.lch.c - mid * reach) < 0.5
                if inside { lo = mid } else { hi = mid }
            }
            return lo
        }
    }

    /// The hue ring's colour at `h`: one lightness and chroma for every hue, inside the gamut.
    public func ringColour(h: Double) -> DelphiColour {
        let (l, r): (Double, Double) = switch self {
        case .oklch: (0.74, 0.12 / 0.33)
        case .lch: (0.74, 48 / 134)
        case .hsl: (0.72, 0.7)
        }
        return colour(l: l, r: min(r, maxRadius(l: l, h: h)), h: h)
    }

    /// The harmony of `(l, r, h)` in this space, in `mode.angles` order: offsets turn the hue; monochromatic steps the
    /// lightness and softens chroma above 0.6, as `DelphiColour.harmony` does in OKLCH.
    public func harmony(l: Double, r: Double, h: Double, mode: HarmonyMode) -> [DelphiColour] {
        if mode == .monochromatic {
            return [0.85, 0.70, l, 0.40, 0.25].map { step in colour(l: step, r: step > 0.6 ? r * 0.7 : r, h: h) }
        }
        return mode.angles.map { offset in
            let hue = (h + offset).truncatingRemainder(dividingBy: 360)
            return colour(l: l, r: r, h: hue < 0 ? hue + 360 : hue)
        }
    }

    /// The harmony of `base`, its chroma cut to the gamut.
    public func harmony(of base: DelphiColour, mode: HarmonyMode) -> [DelphiColour] {
        let parts = parts(of: base)
        return harmony(l: parts.l, r: min(parts.r, maxRadius(l: parts.l, h: parts.h)), h: parts.h, mode: mode)
    }

    #if DEBUG
    public static func selfCheck() {
        let blue = DelphiColour.fromHex("#3B82F6")!
        for space in allCases {
            let parts = space.parts(of: blue)
            let back = space.colour(l: parts.l, r: parts.r, h: parts.h)
            assert(abs(back.r - blue.r) < 0.002 && abs(back.g - blue.g) < 0.002 && abs(back.b - blue.b) < 0.002)
            assert(parts.r <= space.maxRadius(l: parts.l, h: parts.h) + 0.002)
            let triad = space.harmony(l: parts.l, r: parts.r, h: parts.h, mode: .triadic)
            assert(abs(space.parts(of: triad[1]).h - (parts.h + 120).truncatingRemainder(dividingBy: 360)) < 1)
        }
        let model = HarmonyWheelSpace.oklch.harmony(l: 0.6, r: 0.1 / 0.33, h: 40, mode: .complementary)
        let direct = DelphiColour.fromOKLCH(l: 0.6, c: 0.1, h: 220)
        assert(abs(model[1].g - direct.g) < 1e-9)
        // mono softens past 0.6
        let teal = DelphiColour.fromOKLCH(l: 0.5, c: 0.05, h: 200)
        let mono = HarmonyWheelSpace.oklch.harmony(of: teal, mode: .monochromatic)
        assert(mono.count == 5 && abs(mono[0].oklch.c - 0.035) < 0.002 && abs(mono[3].oklch.c - 0.05) < 0.002)
        assert(abs(mono[2].r - teal.r) < 0.002 && abs(mono[2].b - teal.b) < 0.002)
        assert(HarmonyWheelSpace.lch.maxRadius(l: 0.5, h: 40) * 134 > 60 && HarmonyWheelSpace.lch.maxRadius(l: 0.99, h: 40) * 134 < 10)
        assert(DelphiColour.maxChroma(lightness: 1, hue: 264) < 0.001 && DelphiColour.maxChroma(lightness: 0.64, hue: 264) > 0.1)
    }
    #endif
}
