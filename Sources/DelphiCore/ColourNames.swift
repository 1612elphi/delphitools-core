import Foundation

// MARK: - Colour Names

/// Colour naming using meodai/color-names bestof database (4,926 colours).
/// Loaded from a bundled JSON resource at first access.
/// Uses Euclidean RGB distance for nearest-colour matching.
public enum ColourNames {

    private struct JSONEntry: Decodable {
        let name: String
        let hex: String
    }

    private struct Entry {
        let name: String
        let r: Int
        let g: Int
        let b: Int
    }

    /// Lazily loaded database — parsed once on first access.
    private static let database: [Entry] = {
        guard let url = Bundle.module.url(forResource: "colour-names", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let entries = try? JSONDecoder().decode([JSONEntry].self, from: data)
        else { return [] }

        return entries.compactMap { entry in
            let hex = entry.hex.hasPrefix("#") ? String(entry.hex.dropFirst()) : entry.hex
            guard hex.count == 6,
                  let r = Int(hex.prefix(2), radix: 16),
                  let g = Int(hex.dropFirst(2).prefix(2), radix: 16),
                  let b = Int(hex.dropFirst(4).prefix(2), radix: 16)
            else { return nil }
            return Entry(name: entry.name, r: r, g: g, b: b)
        }
    }()

    private static var cache: [Int: String] = [:]
    private static let lock = NSLock()

    /// Find the closest named colour by RGB values (0-255). Memoised: one scan per distinct colour.
    public static func closest(r: Int, g: Int, b: Int) -> String {
        let key = r << 16 | g << 8 | b
        lock.lock()
        let cached = cache[key]
        lock.unlock()
        if let cached { return cached }
        let name = scan(r: r, g: g, b: b)
        lock.lock()
        cache[key] = name
        lock.unlock()
        return name
    }

    private static func scan(r: Int, g: Int, b: Int) -> String {
        var bestName = "Unknown"
        var bestDist = Int.max
        for entry in database {
            let dr = r - entry.r
            let dg = g - entry.g
            let db = b - entry.b
            let dist = dr * dr + dg * dg + db * db
            if dist < bestDist {
                bestDist = dist
                bestName = entry.name
            }
            if dist == 0 { break }
        }
        return bestName
    }

    /// Find the closest named colour from a hex string.
    public static func closest(hex: String) -> String {
        guard let c = DelphiColour.fromHex(hex) else { return "Unknown" }
        let rgb = c.rgb
        return closest(r: rgb.r, g: rgb.g, b: rgb.b)
    }

    /// Find the closest named colour from a DelphiColour.
    public static func closest(_ colour: DelphiColour) -> String {
        let rgb = colour.rgb
        return closest(r: rgb.r, g: rgb.g, b: rgb.b)
    }
}

// MARK: - DelphiColour Extension

extension DelphiColour {
    public var colourName: String {
        ColourNames.closest(self)
    }
}
