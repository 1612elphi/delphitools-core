import Foundation

public enum ColourFormat: String, CaseIterable, Identifiable, Sendable {
    case hex, rgb, hsl, lab, lch, oklab, oklch

    public var id: String { rawValue }

    public var label: String { rawValue.uppercased() }

    public func formatted(_ colour: DelphiColour) -> String {
        switch self {
        case .hex: colour.hex
        case .rgb: colour.rgbString
        case .hsl: colour.hslString
        case .lab: colour.labString
        case .lch: colour.lchString
        case .oklab: colour.oklabString
        case .oklch: colour.oklchString
        }
    }
}
