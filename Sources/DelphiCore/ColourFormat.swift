import Foundation

public enum ColourFormat: String, CaseIterable, Identifiable, Sendable {
    case hex, rgb, hsl, lab, lch, oklab, oklch

    public var id: String { rawValue }

    public var label: String { rawValue.uppercased() }

    /// The matching `ColourExport` template.
    public var exportID: String { self == .hex ? "hex" : "css-\(rawValue)" }

    public func formatted(_ colour: DelphiColour) -> String {
        ColourExport.format(exportID)?.format(colour) ?? colour.hex
    }
}
