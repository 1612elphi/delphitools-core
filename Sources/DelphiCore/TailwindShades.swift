import Foundation

public enum TailwindMode: String, CaseIterable, Identifiable, Sendable {
    case classic, hueShift, luminanceAnchored, vivid, muted

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .classic: "Classic"
        case .hueShift: "Hue Shift"
        case .luminanceAnchored: "Luminance"
        case .vivid: "Vivid"
        case .muted: "Muted"
        }
    }
}

public struct TailwindShade: Identifiable {
    public let step: Int
    public let colour: DelphiColour

    public var id: Int { step }
}

extension DelphiColour {
    // step, OKLCH lightness
    public static let tailwindSteps: [(step: Int, lightness: Double)] = [
        (50, 0.97), (100, 0.93), (200, 0.87), (300, 0.78), (400, 0.66), (500, 0.55),
        (600, 0.47), (700, 0.40), (800, 0.33), (900, 0.27), (950, 0.20),
    ]

    public func tailwindShades(_ mode: TailwindMode) -> [TailwindShade] {
        let base = oklch
        return Self.tailwindSteps.map { step, l in
            var c = base.c
            var h = base.h
            switch mode {
            case .classic:
                if step <= 100 { c *= 0.3 } else if step >= 900 { c *= 0.6 }
            case .hueShift:
                h += (l - 0.55) * 30
                if step <= 100 { c *= 0.4 } else if step >= 900 { c *= 0.7 }
            case .luminanceAnchored:
                if step <= 100 { c *= 0.15 } else if step >= 900 { c *= 0.4 }
            case .vivid:
                c = min(c * 1.1, 0.4)
                if step <= 100 { c *= 0.6 } else if step >= 900 { c *= 0.8 }
            case .muted:
                if step <= 100 { c *= 0.15 } else if step <= 300 { c *= 0.3 } else { c *= 0.5 }
            }
            return TailwindShade(step: step, colour: DelphiColour.fromOKLCH(l: l, c: c, h: h))
        }
    }
}
