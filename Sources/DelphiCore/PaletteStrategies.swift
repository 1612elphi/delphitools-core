import Foundation

public enum PaletteCategory: String, CaseIterable, Identifiable, Sendable {
    case random, colourTheory, mood, era, nature, cultural

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .random: "Random"
        case .colourTheory: "Theory"
        case .mood: "Mood"
        case .era: "Era"
        case .nature: "Nature"
        case .cultural: "Cultural"
        }
    }
}

public struct PaletteStrategy: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let category: PaletteCategory
    /// (count, hue of the first locked colour)
    public let generator: @Sendable (Int, Double?) -> [DelphiColour]

    public static func == (lhs: PaletteStrategy, rhs: PaletteStrategy) -> Bool { lhs.id == rhs.id }
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

public enum PaletteStrategies {
    public static let all: [PaletteStrategy] = random + colourTheory + mood + era + nature + cultural

    public static func strategies(for category: PaletteCategory) -> [PaletteStrategy] {
        all.filter { $0.category == category }
    }

    private static func pick(_ ranges: [(hue: ClosedRange<Double>, weight: Double)], l: ClosedRange<Double>,
                             c: ClosedRange<Double>, count: Int) -> [DelphiColour] {
        let total = ranges.reduce(0) { $0 + $1.weight }
        return (0..<count).map { _ in
            var roll = Double.random(in: 0..<total)
            var hue = ranges[0].hue
            for range in ranges {
                roll -= range.weight
                if roll <= 0 { hue = range.hue; break }
            }
            return DelphiColour.fromOKLCH(l: .random(in: l), c: .random(in: c), h: .random(in: hue))
        }
    }

    private static let random: [PaletteStrategy] = [
        PaletteStrategy(id: "random", name: "True Random", category: .random) { count, _ in
            (0..<count).map { _ in DelphiColour(r: .random(in: 0...1), g: .random(in: 0...1), b: .random(in: 0...1)) }
        },
        PaletteStrategy(id: "random-cohesive", name: "Cohesive Random", category: .random) { count, baseHue in
            colourTheory.randomElement()!.generator(count, baseHue)
        },
    ]

    private static let colourTheory: [PaletteStrategy] = [
        PaletteStrategy(id: "analogous", name: "Analogous", category: .colourTheory) { count, baseHue in
            let base = baseHue ?? .random(in: 0..<360)
            let step = 40.0 / Double(max(count - 1, 1))
            return (0..<count).map { i in
                let offset = Double(i) - Double(count - 1) / 2
                return DelphiColour.fromOKLCH(l: .random(in: 0.4...0.8), c: .random(in: 0.08...0.18), h: base + offset * step)
            }
        },
        PaletteStrategy(id: "complementary", name: "Complementary", category: .colourTheory) { count, baseHue in
            let base = baseHue ?? .random(in: 0..<360)
            return (0..<count).map { i in
                let h = i < count / 2 + 1 ? base + .random(in: -15...15) : base + 180 + .random(in: -15...15)
                return DelphiColour.fromOKLCH(l: .random(in: 0.35...0.85), c: .random(in: 0.08...0.20), h: h)
            }
        },
        PaletteStrategy(id: "triadic", name: "Triadic", category: .colourTheory) { count, baseHue in
            let base = baseHue ?? .random(in: 0..<360)
            return (0..<count).map { i in
                DelphiColour.fromOKLCH(l: .random(in: 0.4...0.8), c: .random(in: 0.08...0.18),
                                       h: base + [0.0, 120, 240][i % 3] + .random(in: -10...10))
            }
        },
        PaletteStrategy(id: "split-complementary", name: "Split-Comp.", category: .colourTheory) { count, baseHue in
            let base = baseHue ?? .random(in: 0..<360)
            let offsets = [0.0, 0, 150, 210, 180]
            return (0..<count).map { i in
                DelphiColour.fromOKLCH(l: .random(in: 0.4...0.8), c: .random(in: 0.08...0.18),
                                       h: base + offsets[i % offsets.count] + .random(in: -8...8))
            }
        },
        PaletteStrategy(id: "tetradic", name: "Tetradic", category: .colourTheory) { count, baseHue in
            let base = baseHue ?? .random(in: 0..<360)
            let offsets = [0.0, 90, 180, 270, 45]
            return (0..<count).map { i in
                DelphiColour.fromOKLCH(l: .random(in: 0.4...0.8), c: .random(in: 0.08...0.18),
                                       h: base + offsets[i % offsets.count])
            }
        },
        PaletteStrategy(id: "monochromatic", name: "Monochromatic", category: .colourTheory) { count, baseHue in
            let h = baseHue ?? .random(in: 0..<360)
            let c = Double.random(in: 0.08...0.18)
            let step = 0.55 / Double(max(count - 1, 1))
            return (0..<count).map { i in DelphiColour.fromOKLCH(l: 0.3 + Double(i) * step, c: c, h: h) }
        },
    ]

    private static let mood: [PaletteStrategy] = [
        PaletteStrategy(id: "thermos", name: "Warm / Cozy", category: .mood) { count, _ in
            pick([(15...55, 1)], l: 0.45...0.75, c: 0.10...0.20, count: count)
        },
        PaletteStrategy(id: "specimen", name: "Cool / Clinical", category: .mood) { count, _ in
            pick([(170...220, 1)], l: 0.50...0.80, c: 0.06...0.14, count: count)
        },
        PaletteStrategy(id: "souvenir", name: "Pastel", category: .mood) { count, _ in
            pick([(0...360, 1)], l: 0.75...0.92, c: 0.04...0.10, count: count)
        },
        PaletteStrategy(id: "curfew", name: "Dark / Moody", category: .mood) { count, _ in
            pick([(0...360, 1)], l: 0.15...0.35, c: 0.05...0.15, count: count)
        },
        PaletteStrategy(id: "telegraph", name: "Sepia / Nostalgic", category: .mood) { count, _ in
            pick([(30...60, 1)], l: 0.40...0.75, c: 0.02...0.08, count: count)
        },
    ]

    private static let era: [PaletteStrategy] = [
        PaletteStrategy(id: "art-deco-era", name: "Art Deco Era", category: .era) { count, _ in
            (0..<count).map { _ in
                let roll = Double.random(in: 0...1)
                if roll < 0.2 { return DelphiColour.fromOKLCH(l: 0.10, c: 0, h: 0) }
                if roll < 0.35 { return DelphiColour.fromOKLCH(l: 0.80, c: 0.08, h: 80) }
                return DelphiColour.fromOKLCH(l: .random(in: 0.35...0.65), c: .random(in: 0.10...0.20),
                                              h: [155.0, 240, 80].randomElement()! + .random(in: -10...10))
            }
        },
        PaletteStrategy(id: "victorian", name: "Victorian", category: .era) { count, _ in
            pick([(340...360, 0.3), (270...290, 0.3), (80...90, 0.2), (140...160, 0.2)], l: 0.25...0.55, c: 0.08...0.16, count: count)
        },
        PaletteStrategy(id: "70s", name: "1970s", category: .era) { count, _ in
            pick([(20...45, 0.4), (80...110, 0.3), (35...55, 0.3)], l: 0.40...0.65, c: 0.10...0.18, count: count)
        },
        PaletteStrategy(id: "80s", name: "1980s Neon", category: .era) { count, _ in
            (0..<count).map { _ in
                if Double.random(in: 0...1) < 0.2 { return DelphiColour.fromOKLCH(l: 0.15, c: 0.01, h: 0) }
                return DelphiColour.fromOKLCH(l: .random(in: 0.65...0.85), c: .random(in: 0.18...0.30),
                                              h: [320.0, 200, 280, 60].randomElement()! + .random(in: -15...15))
            }
        },
        PaletteStrategy(id: "90s", name: "1990s Grunge", category: .era) { count, _ in
            pick([(140...170, 0.3), (340...360, 0.3), (220...240, 0.2), (30...50, 0.2)], l: 0.25...0.50, c: 0.06...0.14, count: count)
        },
        PaletteStrategy(id: "y2k", name: "Y2K", category: .era) { count, _ in
            (0..<count).map { _ in
                if Double.random(in: 0...1) < 0.3 {
                    return DelphiColour.fromOKLCH(l: .random(in: 0.75...0.90), c: .random(in: 0.01...0.03), h: 250)
                }
                return DelphiColour.fromOKLCH(l: .random(in: 0.55...0.80), c: .random(in: 0.12...0.25),
                                              h: [190.0, 320, 270].randomElement()! + .random(in: -10...10))
            }
        },
    ]

    private static let nature: [PaletteStrategy] = [
        PaletteStrategy(id: "ocean-sunset", name: "Ocean Sunset", category: .nature) { count, _ in
            pick([(10...35, 0.3), (200...230, 0.4), (280...310, 0.3)], l: 0.45...0.75, c: 0.10...0.20, count: count)
        },
        PaletteStrategy(id: "forest-morning", name: "Forest Morning", category: .nature) { count, _ in
            (0..<count).map { _ in
                if Double.random(in: 0...1) < 0.25 { return DelphiColour.fromOKLCH(l: .random(in: 0.80...0.92), c: 0.02, h: 100) }
                return DelphiColour.fromOKLCH(l: .random(in: 0.35...0.65), c: .random(in: 0.08...0.16), h: .random(in: 120...160))
            }
        },
        PaletteStrategy(id: "desert-dusk", name: "Desert Dusk", category: .nature) { count, _ in
            pick([(15...35, 0.4), (340...360, 0.3), (270...290, 0.3)], l: 0.40...0.70, c: 0.08...0.16, count: count)
        },
        PaletteStrategy(id: "arctic", name: "Arctic", category: .nature) { count, _ in
            (0..<count).map { _ in
                if Double.random(in: 0...1) < 0.3 { return DelphiColour.fromOKLCH(l: .random(in: 0.92...0.98), c: 0.01, h: 220) }
                return DelphiColour.fromOKLCH(l: .random(in: 0.70...0.90), c: .random(in: 0.03...0.08), h: .random(in: 200...240))
            }
        },
        PaletteStrategy(id: "volcanic", name: "Volcanic", category: .nature) { count, _ in
            (0..<count).map { _ in
                let roll = Double.random(in: 0...1)
                if roll < 0.25 { return DelphiColour.fromOKLCH(l: 0.15, c: 0.01, h: 0) }
                if roll < 0.40 { return DelphiColour.fromOKLCH(l: .random(in: 0.40...0.55), c: 0.02, h: 60) }
                return DelphiColour.fromOKLCH(l: .random(in: 0.40...0.60), c: .random(in: 0.15...0.25), h: .random(in: 15...40))
            }
        },
        PaletteStrategy(id: "tropical", name: "Tropical", category: .nature) { count, _ in
            pick([(120...160, 0.3), (330...350, 0.2), (55...75, 0.2), (190...210, 0.3)], l: 0.50...0.75, c: 0.12...0.25, count: count)
        },
        PaletteStrategy(id: "meadow", name: "Meadow", category: .nature) { count, _ in
            pick([(100...140, 0.3), (310...340, 0.2), (60...80, 0.2), (200...220, 0.3)], l: 0.55...0.80, c: 0.08...0.18, count: count)
        },
    ]

    private static let cultural: [PaletteStrategy] = [
        PaletteStrategy(id: "bauhaus", name: "Bauhaus", category: .cultural) { count, _ in
            (0..<count).map { _ in
                let roll = Double.random(in: 0...1)
                if roll < 0.2 { return DelphiColour.fromOKLCH(l: 0.10, c: 0, h: 0) }
                if roll < 0.3 { return DelphiColour.fromOKLCH(l: 0.95, c: 0.02, h: 80) }
                return DelphiColour.fromOKLCH(l: .random(in: 0.50...0.65), c: .random(in: 0.18...0.28),
                                              h: [30.0, 130, 240].randomElement()! + .random(in: -5...5))
            }
        },
        PaletteStrategy(id: "art-deco", name: "Art Deco", category: .cultural) { count, _ in
            pick([(75...90, 0.3), (0...0, 0.2), (80...85, 0.2), (155...170, 0.3)], l: 0.30...0.75, c: 0.05...0.18, count: count)
        },
        PaletteStrategy(id: "japanese", name: "Japanese", category: .cultural) { count, _ in
            pick([(235...245, 0.2), (20...30, 0.2), (80...90, 0.15), (155...165, 0.15), (285...295, 0.15), (340...350, 0.15)],
                 l: 0.40...0.75, c: 0.08...0.18, count: count)
        },
        PaletteStrategy(id: "scandinavian", name: "Scandinavian", category: .cultural) { count, _ in
            (0..<count).map { _ in
                let roll = Double.random(in: 0...1)
                if roll < 0.35 { return DelphiColour.fromOKLCH(l: .random(in: 0.93...0.98), c: 0.01, h: 80) }
                if roll < 0.55 { return DelphiColour.fromOKLCH(l: .random(in: 0.82...0.90), c: 0.01, h: 240) }
                if roll < 0.75 { return DelphiColour.fromOKLCH(l: .random(in: 0.75...0.88), c: .random(in: 0.03...0.06), h: .random(in: 0..<360)) }
                return DelphiColour.fromOKLCH(l: .random(in: 0.55...0.65), c: .random(in: 0.04...0.08), h: .random(in: 60...90))
            }
        },
        PaletteStrategy(id: "mexican", name: "Mexican Folk Art", category: .cultural) { count, _ in
            pick([(330...345, 0.25), (25...40, 0.2), (180...195, 0.2), (85...95, 0.15), (290...310, 0.2)],
                 l: 0.50...0.70, c: 0.15...0.28, count: count)
        },
    ]
}

/// A generated palette with its strategy and the columns locked against regenerating. Locks are indices, so removing a
/// colour shifts the locks above it down.
public struct PaletteDraft: Sendable {
    public var category: PaletteCategory
    public var strategy: PaletteStrategy
    public var colours: [DelphiColour] = []
    public var locked: Set<Int> = []

    /// Generated with the first strategy of `category`; a `seed` colour takes the first column, locked.
    public init(category: PaletteCategory = .random, count: Int = 5, seed: DelphiColour? = nil) {
        self.category = seed == nil ? category : .colourTheory
        strategy = PaletteStrategies.strategies(for: self.category)[0]
        if let seed {
            colours = [seed]
            locked = [0]
        }
        generate(count: count)
    }

    public static let counts = 3...12

    /// The hue of the first locked colour, for the colour-theory strategies.
    private var lockedHue: Double? {
        locked.min().flatMap { colours.indices.contains($0) ? colours[$0].oklch.h : nil }
    }

    /// New colours from the strategy; locked columns keep theirs.
    public mutating func generate(count: Int? = nil) {
        let count = count ?? colours.count
        var fresh = strategy.generator(count, lockedHue)
        for index in locked where index < min(colours.count, fresh.count) { fresh[index] = colours[index] }
        colours = fresh
        locked = locked.filter { $0 < count }
    }

    public mutating func select(_ category: PaletteCategory) {
        self.category = category
        select(PaletteStrategies.strategies(for: category)[0])
    }

    public mutating func select(_ strategy: PaletteStrategy) {
        self.strategy = strategy
        category = strategy.category
        generate()
    }

    /// Adds colours at the end without touching the rest, or drops them from the end.
    public mutating func resize(to target: Int) {
        let target = min(max(target, Self.counts.lowerBound), Self.counts.upperBound)
        guard target > colours.count else {
            colours.removeLast(colours.count - target)
            locked = locked.filter { $0 < target }
            return
        }
        colours += strategy.generator(target - colours.count, lockedHue)
    }

    public mutating func remove(at index: Int) {
        guard colours.indices.contains(index), colours.count > Self.counts.lowerBound else { return }
        colours.remove(at: index)
        locked = Set(locked.compactMap { $0 == index ? nil : $0 > index ? $0 - 1 : $0 })
    }

    public mutating func toggleLock(_ index: Int) {
        if locked.remove(index) == nil { locked.insert(index) }
    }

    /// A colour set by hand, locked.
    public mutating func set(_ colour: DelphiColour, at index: Int) {
        guard colours.indices.contains(index) else { return }
        colours[index] = colour
        locked.insert(index)
    }

    #if DEBUG
    public static func selfCheck() {
        var draft = PaletteDraft()
        let before = draft.colours
        assert(before.count == 5)
        draft.locked = [1]
        draft.resize(to: 8)
        assert(draft.colours.count == 8 && Array(draft.colours.prefix(5)) == before && draft.locked == [1])
        draft.resize(to: 4)
        assert(draft.colours == Array(before.prefix(4)) && draft.locked == [1])
        draft.resize(to: 1)
        assert(draft.colours.count == 3)
        draft.locked = [0, 2]
        draft.remove(at: 1)
        assert(draft.colours.count == 3)
        draft.resize(to: 5)
        draft.remove(at: 1)
        assert(draft.colours.count == 4 && draft.locked == [0, 1])
        draft.generate()
        assert(draft.colours[0] == before[0] && draft.colours[1] == before[2])
        let seed = DelphiColour(r: 1, g: 0, b: 0)
        let seeded = PaletteDraft(seed: seed)
        assert(seeded.category == .colourTheory && seeded.colours[0] == seed && seeded.locked == [0] && seeded.colours.count == 5)
        draft.select(.mood)
        assert(draft.strategy.category == .mood && draft.colours.count == 4)
        assert(PaletteFiles.ase(name: "a", colours: [seed]).prefix(4) == Data("ASEF".utf8))
        let swatches = PaletteFiles.procreate(name: "a", colours: [seed])
        assert(swatches.prefix(4) == Data([0x50, 0x4B, 0x03, 0x04]) && PaletteFiles.crc32(Data("123456789".utf8)) == 0xCBF4_3926)
    }
    #endif
}

/// Palette files: Adobe Swatch Exchange (.ase) and Procreate Swatches (.swatches, a zip of Swatches.json).
public enum PaletteFiles {
    public static func css(name: String, colours: [DelphiColour]) -> String {
        (["/* \(name) */"] + colours.enumerated().map { "--palette-\($0.offset + 1): \($0.element.hex);" }).joined(separator: "\n")
    }

    public static func ase(name: String, colours: [DelphiColour]) -> Data {
        var data = Data("ASEF".utf8)
        data.big(UInt16(1))
        data.big(UInt16(0))
        // group start, colours, group end
        data.big(UInt32(2 + colours.count))
        let group = utf16(name)
        data.big(UInt16(0xC001))
        data.big(UInt32(group.count))
        data.append(group)
        for colour in colours {
            let label = utf16(colour.colourName)
            data.big(UInt16(0x0001))
            // name, model, three floats, type
            data.big(UInt32(label.count + 4 + 12 + 2))
            data.append(label)
            data.append(Data("RGB ".utf8))
            for value in [colour.r, colour.g, colour.b] { data.big(Float32(min(max(value, 0), 1)).bitPattern) }
            // process colour
            data.big(UInt16(2))
        }
        data.big(UInt16(0xC002))
        data.big(UInt32(0))
        return data
    }

    public static func procreate(name: String, colours: [DelphiColour]) -> Data {
        // procreate holds 30
        let swatches = colours.prefix(30).map { colour -> [String: Any] in
            let (r, g, b) = (min(max(colour.r, 0), 1), min(max(colour.g, 0), 1), min(max(colour.b, 0), 1))
            let most = max(r, g, b), delta = most - min(r, g, b)
            var hue = 0.0
            if delta > 0 {
                hue = most == r ? (g - b) / delta : most == g ? (b - r) / delta + 2 : (r - g) / delta + 4
                hue = (hue / 6).truncatingRemainder(dividingBy: 1)
                if hue < 0 { hue += 1 }
            }
            return ["hue": hue, "saturation": most > 0 ? delta / most : 0, "brightness": most, "alpha": 1, "colorSpace": 0]
        }
        let json = (try? JSONSerialization.data(withJSONObject: [["name": name, "swatches": swatches]])) ?? Data()
        return zip(filename: "Swatches.json", contents: json)
    }

    // length-prefixed, nul-terminated
    private static func utf16(_ string: String) -> Data {
        var data = Data()
        let units = Array(string.utf16)
        data.big(UInt16(units.count + 1))
        units.forEach { data.big($0) }
        data.big(UInt16(0))
        return data
    }

    /// One stored file: local header, central directory, end record.
    private static func zip(filename: String, contents: Data) -> Data {
        let name = Data(filename.utf8)
        let crc = crc32(contents), size = UInt32(contents.count)
        var zip = Data([0x50, 0x4B, 0x03, 0x04])
        for value: UInt16 in [20, 0, 0, 0, 0] { zip.little(value) }
        for value in [crc, size, size] { zip.little(value) }
        zip.little(UInt16(name.count))
        zip.little(UInt16(0))
        zip.append(name)
        zip.append(contents)
        let directory = UInt32(zip.count)
        zip.append(contentsOf: [0x50, 0x4B, 0x01, 0x02])
        for value: UInt16 in [20, 20, 0, 0, 0, 0] { zip.little(value) }
        for value in [crc, size, size] { zip.little(value) }
        for value: UInt16 in [UInt16(name.count), 0, 0, 0, 0] { zip.little(value) }
        zip.little(UInt32(0))
        zip.little(UInt32(0))
        zip.append(name)
        let directorySize = UInt32(zip.count) - directory
        zip.append(contentsOf: [0x50, 0x4B, 0x05, 0x06])
        for value: UInt16 in [0, 0, 1, 1] { zip.little(value) }
        zip.little(directorySize)
        zip.little(directory)
        zip.little(UInt16(0))
        return zip
    }

    static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 { crc = (crc >> 1) ^ (crc & 1 != 0 ? 0xEDB8_8320 : 0) }
        }
        return crc ^ 0xFFFF_FFFF
    }
}

private extension Data {
    mutating func big<T: FixedWidthInteger>(_ value: T) {
        Swift.withUnsafeBytes(of: value.bigEndian) { append(contentsOf: $0) }
    }

    mutating func little<T: FixedWidthInteger>(_ value: T) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }
}
