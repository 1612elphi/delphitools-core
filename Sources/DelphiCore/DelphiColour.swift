#if canImport(AppKit)
import AppKit
#endif
import SwiftUI

// MARK: - DelphiColour

/// Unified colour model with manual conversions for all colour spaces.
/// Uses sRGB as the hub format. Supports Display P3 where available.
public struct DelphiColour: Equatable, Hashable {
    /// sRGB components 0–1
    public var r: Double
    public var g: Double
    public var b: Double
    public var a: Double = 1.0

    public init(r: Double, g: Double, b: Double, a: Double = 1.0) {
        self.r = r
        self.g = g
        self.b = b
        self.a = a
    }

    // MARK: - Hex

    public var hex: String {
        String(format: "#%02X%02X%02X",
               Int(round(clamp01(r) * 255)),
               Int(round(clamp01(g) * 255)),
               Int(round(clamp01(b) * 255)))
    }

    public var hexNoHash: String { String(hex.dropFirst()) }

    public static func fromHex(_ hex: String) -> DelphiColour? {
        var cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("#") { cleaned = String(cleaned.dropFirst()) }
        guard cleaned.count == 6,
              let ri = UInt8(cleaned.prefix(2), radix: 16),
              let gi = UInt8(cleaned.dropFirst(2).prefix(2), radix: 16),
              let bi = UInt8(cleaned.dropFirst(4).prefix(2), radix: 16)
        else { return nil }
        return DelphiColour(r: Double(ri) / 255, g: Double(gi) / 255, b: Double(bi) / 255)
    }

    // MARK: - RGB

    public var rgb: (r: Int, g: Int, b: Int) {
        (Int(round(clamp01(r) * 255)),
         Int(round(clamp01(g) * 255)),
         Int(round(clamp01(b) * 255)))
    }

    public var rgbString: String {
        let c = rgb
        return "rgb(\(c.r), \(c.g), \(c.b))"
    }

    // MARK: - HSL

    public var hsl: (h: Double, s: Double, l: Double) {
        let r0 = clamp01(r), g0 = clamp01(g), b0 = clamp01(b)
        let cmax = max(r0, g0, b0)
        let cmin = min(r0, g0, b0)
        let delta = cmax - cmin
        let l = (cmax + cmin) / 2
        guard delta > 1e-10 else { return (0, 0, l * 100) }
        let s = delta / (1 - abs(2 * l - 1))
        var h: Double
        if cmax == r0 {
            h = 60 * (((g0 - b0) / delta).truncatingRemainder(dividingBy: 6))
        } else if cmax == g0 {
            h = 60 * ((b0 - r0) / delta + 2)
        } else {
            h = 60 * ((r0 - g0) / delta + 4)
        }
        if h < 0 { h += 360 }
        return (h, s * 100, l * 100)
    }

    public var hslString: String {
        let c = hsl
        return String(format: "hsl(%.0f, %.0f%%, %.0f%%)", c.h, c.s, c.l)
    }

    public static func fromHSL(h: Double, s: Double, l: Double) -> DelphiColour {
        let s1 = s / 100, l1 = l / 100
        let c = (1 - abs(2 * l1 - 1)) * s1
        let x = c * (1 - abs((h / 60).truncatingRemainder(dividingBy: 2) - 1))
        let m = l1 - c / 2
        let (r1, g1, b1): (Double, Double, Double)
        switch h {
        case 0..<60:    (r1, g1, b1) = (c, x, 0)
        case 60..<120:  (r1, g1, b1) = (x, c, 0)
        case 120..<180: (r1, g1, b1) = (0, c, x)
        case 180..<240: (r1, g1, b1) = (0, x, c)
        case 240..<300: (r1, g1, b1) = (x, 0, c)
        default:        (r1, g1, b1) = (c, 0, x)
        }
        return DelphiColour(r: r1 + m, g: g1 + m, b: b1 + m)
    }

    // MARK: - Linear sRGB

    private var linearRGB: (r: Double, g: Double, b: Double) {
        (srgbToLinear(clamp01(r)), srgbToLinear(clamp01(g)), srgbToLinear(clamp01(b)))
    }

    private static func fromLinearRGB(_ lr: Double, _ lg: Double, _ lb: Double) -> DelphiColour {
        DelphiColour(r: linearToSrgb(lr), g: linearToSrgb(lg), b: linearToSrgb(lb))
    }

    // MARK: - XYZ (D65)

    private static let d65White: (x: Double, y: Double, z: Double) = (0.95047, 1.0, 1.08883)

    public var xyz: (x: Double, y: Double, z: Double) {
        let lin = linearRGB
        let x = 0.4124564 * lin.r + 0.3575761 * lin.g + 0.1804375 * lin.b
        let y = 0.2126729 * lin.r + 0.7151522 * lin.g + 0.0721750 * lin.b
        let z = 0.0193339 * lin.r + 0.1191920 * lin.g + 0.9503041 * lin.b
        return (x, y, z)
    }

    private static func fromXYZ(_ x: Double, _ y: Double, _ z: Double) -> DelphiColour {
        let lr =  3.2404542 * x - 1.5371385 * y - 0.4985314 * z
        let lg = -0.9692660 * x + 1.8760108 * y + 0.0415560 * z
        let lb =  0.0556434 * x - 0.2040259 * y + 1.0572252 * z
        return fromLinearRGB(lr, lg, lb)
    }

    // MARK: - CIE LAB

    public var lab: (l: Double, a: Double, b: Double) {
        let c = xyz
        let w = Self.d65White
        let fx = labF(c.x / w.x)
        let fy = labF(c.y / w.y)
        let fz = labF(c.z / w.z)
        return (116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz))
    }

    public var labString: String {
        let c = lab
        return String(format: "lab(%.1f %.1f %.1f)", c.l, c.a, c.b)
    }

    public static func fromLAB(l: Double, a: Double, b: Double) -> DelphiColour {
        let fy = (l + 16) / 116
        let fx = a / 500 + fy
        let fz = fy - b / 200
        let w = d65White
        let x = w.x * labFInv(fx)
        let y = w.y * labFInv(fy)
        let z = w.z * labFInv(fz)
        return fromXYZ(x, y, z)
    }

    // MARK: - CIE LCH

    public var lch: (l: Double, c: Double, h: Double) {
        let c = lab
        let chroma = sqrt(c.a * c.a + c.b * c.b)
        var hue = atan2(c.b, c.a) * 180 / .pi
        if hue < 0 { hue += 360 }
        return (c.l, chroma, hue)
    }

    public var lchString: String {
        let c = lch
        return String(format: "lch(%.1f %.1f %.1f)", c.l, c.c, c.h)
    }

    public static func fromLCH(l: Double, c: Double, h: Double) -> DelphiColour {
        let hRad = h * .pi / 180
        return fromLAB(l: l, a: c * cos(hRad), b: c * sin(hRad))
    }

    // MARK: - OKLAB

    public var oklab: (l: Double, a: Double, b: Double) {
        let lin = linearRGB
        let l_ = 0.4122214708 * lin.r + 0.5363325363 * lin.g + 0.0514459929 * lin.b
        let m_ = 0.2119034982 * lin.r + 0.6806995451 * lin.g + 0.1073969566 * lin.b
        let s_ = 0.0883024619 * lin.r + 0.2817188376 * lin.g + 0.6299787005 * lin.b
        let l = cbrt(l_)
        let m = cbrt(m_)
        let s = cbrt(s_)
        return (
            0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
            1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
            0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s
        )
    }

    public var oklabString: String {
        let c = oklab
        return String(format: "oklab(%.4f %.4f %.4f)", c.l, c.a, c.b)
    }

    public static func fromOKLAB(l: Double, a: Double, b: Double) -> DelphiColour {
        let l_ = l + 0.3963377774 * a + 0.2158037573 * b
        let m_ = l - 0.1055613458 * a - 0.0638541728 * b
        let s_ = l - 0.0894841775 * a - 1.2914855480 * b
        let lc = l_ * l_ * l_
        let mc = m_ * m_ * m_
        let sc = s_ * s_ * s_
        let lr =  4.0767416621 * lc - 3.3077115913 * mc + 0.2309699292 * sc
        let lg = -1.2684380046 * lc + 2.6097574011 * mc - 0.3413193965 * sc
        let lb = -0.0041960863 * lc - 0.7034186147 * mc + 1.7076147010 * sc
        return fromLinearRGB(lr, lg, lb)
    }

    // MARK: - OKLCH

    public var oklch: (l: Double, c: Double, h: Double) {
        let ok = oklab
        let chroma = sqrt(ok.a * ok.a + ok.b * ok.b)
        var hue = atan2(ok.b, ok.a) * 180 / .pi
        if hue < 0 { hue += 360 }
        return (ok.l, chroma, hue)
    }

    public var oklchString: String {
        let c = oklch
        return String(format: "oklch(%.4f %.4f %.1f)", c.l, c.c, c.h)
    }

    public static func fromOKLCH(l: Double, c: Double, h: Double) -> DelphiColour {
        let hRad = h * .pi / 180
        return fromOKLAB(l: l, a: c * cos(hRad), b: c * sin(hRad))
    }

    // MARK: - SwiftUI Colour

    public var color: Color {
        Color(red: clamp01(r), green: clamp01(g), blue: clamp01(b), opacity: a)
    }

    public var displayP3Color: Color {
        Color(.displayP3, red: clamp01(r), green: clamp01(g), blue: clamp01(b), opacity: a)
    }

    public static func fromColor(_ color: Color) -> DelphiColour {
        var rv: CGFloat = 0, gv: CGFloat = 0, bv: CGFloat = 0, av: CGFloat = 0
        #if canImport(UIKit)
        UIColor(color).getRed(&rv, green: &gv, blue: &bv, alpha: &av)
        #else
        (NSColor(color).usingColorSpace(.sRGB) ?? NSColor(color)).getRed(&rv, green: &gv, blue: &bv, alpha: &av)
        #endif
        return DelphiColour(r: Double(rv), g: Double(gv), b: Double(bv), a: Double(av))
    }

    // MARK: - WCAG Relative Luminance

    public var relativeLuminance: Double {
        let lin = linearRGB
        return 0.2126 * lin.r + 0.7152 * lin.g + 0.0722 * lin.b
    }

    public static func contrastRatio(_ c1: DelphiColour, _ c2: DelphiColour) -> Double {
        let l1 = c1.relativeLuminance
        let l2 = c2.relativeLuminance
        let lighter = max(l1, l2)
        let darker = min(l1, l2)
        return (lighter + 0.05) / (darker + 0.05)
    }

    // MARK: - OKLab Interpolation

    public static func lerpOKLab(_ c1: DelphiColour, _ c2: DelphiColour, t: Double) -> DelphiColour {
        let ok1 = c1.oklab
        let ok2 = c2.oklab
        return fromOKLAB(
            l: ok1.l + (ok2.l - ok1.l) * t,
            a: ok1.a + (ok2.a - ok1.a) * t,
            b: ok1.b + (ok2.b - ok1.b) * t
        )
    }

    // MARK: - Colour Blindness Simulation

    public func simulateColourBlindness(_ type: ColourBlindnessType) -> DelphiColour {
        let matrix = type.matrix
        let ri = clamp01(r), gi = clamp01(g), bi = clamp01(b)
        return DelphiColour(
            r: clamp01(matrix[0][0] * ri + matrix[0][1] * gi + matrix[0][2] * bi),
            g: clamp01(matrix[1][0] * ri + matrix[1][1] * gi + matrix[1][2] * bi),
            b: clamp01(matrix[2][0] * ri + matrix[2][1] * gi + matrix[2][2] * bi),
            a: a
        )
    }
}

// MARK: - Helpers

private func clamp01(_ v: Double) -> Double {
    min(max(v, 0), 1)
}

private func srgbToLinear(_ v: Double) -> Double {
    v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
}

private func linearToSrgb(_ v: Double) -> Double {
    let c = max(0, v)
    return c <= 0.0031308 ? 12.92 * c : 1.055 * pow(c, 1.0 / 2.4) - 0.055
}

private func labF(_ t: Double) -> Double {
    let delta: Double = 6.0 / 29.0
    return t > delta * delta * delta ? cbrt(t) : t / (3 * delta * delta) + 4.0 / 29.0
}

private func labFInv(_ t: Double) -> Double {
    let delta: Double = 6.0 / 29.0
    return t > delta ? t * t * t : 3 * delta * delta * (t - 4.0 / 29.0)
}

// MARK: - Colour Blindness Types

public enum ColourBlindnessType: String, CaseIterable, Identifiable {
    case normal
    case protanopia
    case deuteranopia
    case tritanopia
    case protanomaly
    case deuteranomaly
    case tritanomaly
    case achromatopsia
    case achromatomaly

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .normal: "Normal Vision"
        case .protanopia: "Protanopia"
        case .deuteranopia: "Deuteranopia"
        case .tritanopia: "Tritanopia"
        case .protanomaly: "Protanomaly"
        case .deuteranomaly: "Deuteranomaly"
        case .tritanomaly: "Tritanomaly"
        case .achromatopsia: "Achromatopsia"
        case .achromatomaly: "Achromatomaly"
        }
    }

    public var severity: String {
        switch self {
        case .normal: "None"
        case .protanopia, .deuteranopia, .tritanopia, .achromatopsia: "Full"
        case .protanomaly, .deuteranomaly, .tritanomaly, .achromatomaly: "Partial"
        }
    }

    public var shortDescription: String {
        switch self {
        case .normal: "Full colour vision"
        case .protanopia: "Red-blind (~1% AMAB)"
        case .deuteranopia: "Green-blind (~1% AMAB)"
        case .tritanopia: "Blue-blind (~0.003%)"
        case .protanomaly: "Red-weak (~1% AMAB)"
        case .deuteranomaly: "Green-weak (~5% AMAB)"
        case .tritanomaly: "Blue-weak (~0.01%)"
        case .achromatopsia: "Total colour blindness (~0.003%)"
        case .achromatomaly: "Partial colour blindness (very rare)"
        }
    }

    public var matrix: [[Double]] {
        switch self {
        case .normal:
            [[1, 0, 0], [0, 1, 0], [0, 0, 1]]
        case .protanopia:
            [[0.567, 0.433, 0], [0.558, 0.442, 0], [0, 0.242, 0.758]]
        case .deuteranopia:
            [[0.625, 0.375, 0], [0.7, 0.3, 0], [0, 0.3, 0.7]]
        case .tritanopia:
            [[0.95, 0.05, 0], [0, 0.433, 0.567], [0, 0.475, 0.525]]
        case .protanomaly:
            [[0.817, 0.183, 0], [0.333, 0.667, 0], [0, 0.125, 0.875]]
        case .deuteranomaly:
            [[0.8, 0.2, 0], [0.258, 0.742, 0], [0, 0.142, 0.858]]
        case .tritanomaly:
            [[0.967, 0.033, 0], [0, 0.733, 0.267], [0, 0.183, 0.817]]
        case .achromatopsia:
            [[0.299, 0.587, 0.114], [0.299, 0.587, 0.114], [0.299, 0.587, 0.114]]
        case .achromatomaly:
            [[0.618, 0.320, 0.062], [0.163, 0.775, 0.062], [0.163, 0.320, 0.516]]
        }
    }
}
