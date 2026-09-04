import Foundation

extension DelphiColour {
    /// Accepts `#RGB`, `#RRGGBB`, bare 3 or 6 hex digits, and `rgb`/`hsl`/`lab`/`lch`/`oklab`/`oklch` with or without parentheses, commas, or `%`.
    public static func parse(_ text: String) -> DelphiColour? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !t.isEmpty else { return nil }
        let numbers = t.split(whereSeparator: { !$0.isNumber && $0 != "." && $0 != "-" }).compactMap { Double($0) }
        if let prefix = ["oklab", "oklch", "rgb", "hsl", "lab", "lch"].first(where: t.hasPrefix) {
            guard numbers.count == 3 else { return nil }
            let (a, b, c) = (numbers[0], numbers[1], numbers[2])
            switch prefix {
            case "oklab": return fromOKLAB(l: a, a: b, b: c)
            case "oklch": return fromOKLCH(l: a, c: b, h: c)
            case "rgb": return DelphiColour(r: a / 255, g: b / 255, b: c / 255)
            case "hsl": return fromHSL(h: a, s: b, l: c)
            case "lab": return fromLAB(l: a, a: b, b: c)
            default: return fromLCH(l: a, c: b, h: c)
            }
        }
        var hex = t.hasPrefix("#") ? String(t.dropFirst()) : t
        guard hex.allSatisfy(\.isHexDigit), hex.count == 3 || hex.count == 6 else { return nil }
        if hex.count == 3 { hex = hex.map { "\($0)\($0)" }.joined() }
        return fromHex(hex)
    }
}
