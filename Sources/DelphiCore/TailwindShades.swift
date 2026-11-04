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

    /// Share of the base's saturation at the light end, across the middle and at the dark end; above 1 pushes to the
    /// gamut edge.
    var ramp: (light: Double, mid: Double, dark: Double) {
        switch self {
        case .classic, .hueShift: (0.75, 1, 0.85)
        case .luminanceAnchored: (0.5, 1, 0.6)
        case .vivid: (1, 1.35, 1.15)
        case .muted: (0.3, 0.5, 0.4)
        }
    }
}

public struct TailwindShade: Identifiable, Sendable {
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

    /// The 50 to 950 scale, as the web tool builds it: each level keeps a share of the base's saturation (chroma over
    /// the most the gamut holds at that lightness and hue), eased over two levels at each end.
    public func tailwindShades(_ mode: TailwindMode) -> [TailwindShade] {
        let lch = oklch
        let most = Self.maxChroma(lightness: lch.l, hue: lch.h)
        let saturation = most > 0 ? min(1, lch.c / most) : 0
        let steps = Self.tailwindSteps
        return steps.enumerated().map { index, entry in
            let target = entry.lightness
            let fromEnd = steps.count - 1 - index
            let l = mode != .luminanceAnchored ? target
                : index < 2 ? target + (1 - target) * 0.3
                : fromEnd < 2 ? target * 0.8
                : target
            // warm light, cool dark
            let h = mode == .hueShift ? (lch.h + (target - 0.5) * 2 * 15 + 360).truncatingRemainder(dividingBy: 360) : lch.h
            let share = min(1, saturation * TailwindScale.rampScale(index, mode))
            return TailwindShade(step: entry.step, colour: .fromOKLCH(l: l, c: share * Self.maxChroma(lightness: l, hue: h), h: h))
        }
    }
}

public enum TailwindScale {
    // stepping made 100 grey
    static func rampScale(_ index: Int, _ mode: TailwindMode) -> Double {
        let (light, mid, dark) = mode.ramp
        let fromEnd = DelphiColour.tailwindSteps.count - 1 - index
        if index < 2 { return light + (mid - light) * Double(index) / 2 }
        if fromEnd < 2 { return dark + (mid - dark) * Double(fromEnd) / 2 }
        return mid
    }

    /// Where lightness `l` falls on a scale of falling lightnesses: a fractional index, the level it reads as (to 10),
    /// and the nearest step.
    public static func place(lightness l: Double, in scale: [Double]) -> (index: Double, level: Int, nearest: Int) {
        let steps = DelphiColour.tailwindSteps.map(\.step)
        guard scale.count == steps.count, let first = scale.first, let last = scale.last else { return (5, 500, 5) }
        var index = 0.0
        if l >= first {
            index = 0
        } else if l <= last {
            index = Double(scale.count - 1)
        } else if let upper = scale.indices.dropLast().first(where: { scale[$0] >= l && scale[$0 + 1] <= l }) {
            let span = scale[upper] - scale[upper + 1]
            index = Double(upper) + (span > 0 ? (scale[upper] - l) / span : 0)
        }
        let lower = Int(index.rounded(.down)), upper = min(lower + 1, steps.count - 1)
        let level = Double(steps[lower]) + Double(steps[upper] - steps[lower]) * (index - Double(lower))
        return (index, Int((level / 10).rounded()) * 10, Int(index.rounded()))
    }

    #if DEBUG
    public static func selfCheck() {
        let blue = DelphiColour.fromHex("#3B82F6")!
        for mode in TailwindMode.allCases {
            let scale = blue.tailwindShades(mode).map(\.colour.oklch)
            let saturations = scale.map { $0.c / max(DelphiColour.maxChroma(lightness: $0.l, hue: $0.h), 1e-9) }
            for index in 1..<(saturations.count - 1) {
                assert(saturations[index] >= min(saturations[index - 1], saturations[index + 1]) - 1e-3)
            }
            assert(saturations.allSatisfy { $0 <= 1 + 1e-3 })
        }
        assert(abs(rampScale(1, .classic) - 0.875) < 1e-12 && rampScale(0, .classic) == 0.75 && rampScale(10, .classic) == 0.85)
        let grey = DelphiColour(r: 0.5, g: 0.5, b: 0.5).tailwindShades(.vivid)
        assert(grey.allSatisfy { $0.colour.oklch.c < 1e-3 })
        let targets = DelphiColour.tailwindSteps.map(\.lightness)
        assert(place(lightness: 0.55, in: targets) == (5, 500, 5))
        assert(place(lightness: 0.99, in: targets) == (0, 50, 0))
        assert(place(lightness: 0.05, in: targets) == (10, 950, 10))
        let between = place(lightness: 0.605, in: targets)
        assert(abs(between.index - 4.5) < 1e-9 && between.level == 450 && between.nearest == 5)
        assert(place(lightness: 0.95, in: targets).level == 80)
    }
    #endif
}
