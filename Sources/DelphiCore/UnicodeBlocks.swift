import CoreGraphics
import Foundation

/// The Unicode 18.0 blocks (Blocks.txt), search over them, and the layout of a glyph chart of them.
public enum UnicodeBlocks {
    public struct Block: Sendable, Equatable {
        public let name: String
        public let range: ClosedRange<UInt32>

        public init(name: String, range: ClosedRange<UInt32>) {
            self.name = name
            self.range = range
        }
    }

    public static let all: [Block] = {
        guard let url = Bundle.module.url(forResource: "unicode-blocks", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let rows = try? JSONSerialization.jsonObject(with: data) as? [[Any]] else { return [] }
        return rows.compactMap { row in
            guard row.count == 3, let start = row[0] as? Int, let end = row[1] as? Int, let name = row[2] as? String else { return nil }
            return Block(name: name, range: UInt32(start)...UInt32(end))
        }
    }()

    /// The blocks with something to show, and a chart section for each.
    public static let chart: (blocks: [Block], sections: [Section]) = {
        let pairs = all.map { ($0, Section(title: $0.name, range: $0.range)) }.filter { !$0.1.isEmpty }
        return (pairs.map(\.0), pairs.map(\.1))
    }()

    public static func index(containing codePoint: UInt32, in blocks: [Block]) -> Int? {
        blocks.firstIndex { $0.range.contains(codePoint) }
    }

    public enum Find: Equatable, Sendable {
        case codePoint(UInt32)
        case block(Int)
    }

    /// A U+ or 0x code, a single character, four to six hex digits, or part of a block name.
    public static func find(_ query: String, in blocks: [Block]) -> Find? {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return nil }
        let lower = query.lowercased()
        for prefix in ["u+", "0x"] where lower.hasPrefix(prefix) {
            return UInt32(lower.dropFirst(2), radix: 16).flatMap(Unicode.Scalar.init).map { .codePoint($0.value) }
        }
        if query.unicodeScalars.count == 1, let scalar = query.unicodeScalars.first { return .codePoint(scalar.value) }
        if (4...6).contains(query.count), let value = UInt32(query, radix: 16), let scalar = Unicode.Scalar(value) {
            return .codePoint(scalar.value)
        }
        return blocks.firstIndex { $0.name.lowercased().contains(lower) }.map { .block($0) }
    }

    /// The general category in words, untranslated like the names.
    public static func category(_ scalar: Unicode.Scalar) -> String {
        let raw = "\(scalar.properties.generalCategory)"
        var words = ""
        for character in raw {
            if character.isUppercase { words.append(" ") }
            words.append(character)
        }
        return words.prefix(1).uppercased() + words.dropFirst()
    }

    public static func label(_ codePoint: UInt32) -> String { String(format: "U+%04X", codePoint) }

    /// astral needs braced form
    public static func js(_ codePoint: UInt32) -> String {
        codePoint <= 0xFFFF ? String(format: "\\u%04X", codePoint) : String(format: "\\u{%X}", codePoint)
    }

    public static func isVisible(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.properties.generalCategory {
        case .control, .format, .surrogate, .privateUse, .unassigned, .lineSeparator, .paragraphSeparator: false
        default: true
        }
    }

    /// A combining mark on a dotted circle, anything else as itself.
    public static func shown(_ scalar: Unicode.Scalar) -> String {
        switch scalar.properties.generalCategory {
        case .nonspacingMark, .enclosingMark, .spacingMark: "\u{25CC}" + String(scalar)
        default: String(scalar)
        }
    }

    /// A chart section: a titled range and, per row of sixteen, a mask of the code points it shows.
    public struct Section: Sendable, Equatable {
        public var title: String?
        public var range: ClosedRange<UInt32>
        public var masks: [UInt16]

        public init(title: String?, range: ClosedRange<UInt32>) {
            self.title = title
            self.range = range
            let first = range.lowerBound / 16
            masks = (first...(range.upperBound / 16)).map { row in
                var mask: UInt16 = 0
                for bit in 0..<16 {
                    let value = row * 16 + UInt32(bit)
                    if range.contains(value), let scalar = Unicode.Scalar(value), UnicodeBlocks.isVisible(scalar) { mask |= 1 << bit }
                }
                return mask
            }
        }

        public var isEmpty: Bool { masks.allSatisfy { $0 == 0 } }

        public func shows(_ codePoint: UInt32) -> Bool {
            guard range.contains(codePoint) else { return false }
            return masks[Int(codePoint / 16 - range.lowerBound / 16)] & (1 << (codePoint % 16)) != 0
        }
    }

    /// Chart rows top to bottom: a heading per section, then a row per sixteen (or eight) code points with any shown.
    public struct Geometry: Sendable {
        public static let digits: CGFloat = 24
        public static let heading: CGFloat = 58
        public static let rowHeader: CGFloat = 52
        public static let minCell: CGFloat = 34

        public enum Item: Equatable, Sendable {
            case heading(section: Int)
            case row(start: UInt32, section: Int)
        }

        public let columns: Int
        public let cell: CGFloat
        public let width: CGFloat
        public let items: [Item]
        /// Each item's top, then the total height.
        public let tops: [CGFloat]

        public init(sections: [Section], width: CGFloat) {
            let room = max(0, width - Self.rowHeader)
            columns = room / 16 >= Self.minCell ? 16 : 8
            cell = room / CGFloat(columns)
            self.width = width
            var items: [Item] = []
            var tops: [CGFloat] = []
            var y: CGFloat = 0
            for (index, section) in sections.enumerated() where !section.isEmpty {
                items.append(.heading(section: index))
                tops.append(y)
                y += section.title == nil ? Self.digits : Self.heading
                let base = section.range.lowerBound / 16 * 16
                for (row, mask) in section.masks.enumerated() {
                    let start = base + UInt32(row * 16)
                    for half in 0..<(16 / columns) {
                        let bits = columns == 16 ? mask : (mask >> (half * 8)) & 0xFF
                        guard bits != 0 else { continue }
                        items.append(.row(start: start + UInt32(half * columns), section: index))
                        tops.append(y)
                        y += cell
                    }
                }
            }
            tops.append(y)
            self.items = items
            self.tops = tops
        }

        public var height: CGFloat { tops.last ?? 0 }

        public func height(of index: Int) -> CGFloat { tops[index + 1] - tops[index] }

        public func item(at y: CGFloat) -> Int? {
            guard !items.isEmpty, y >= 0, y < height else { return nil }
            var low = 0
            var high = items.count - 1
            while low < high {
                let middle = (low + high + 1) / 2
                if tops[middle] <= y { low = middle } else { high = middle - 1 }
            }
            return low
        }

        public func row(of codePoint: UInt32) -> Int? {
            var low = 0
            var high = items.count - 1
            var found: Int?
            while low <= high {
                let middle = (low + high) / 2
                var probe = middle
                while probe <= high, case .heading = items[probe] { probe += 1 }
                guard probe <= high, case .row(let start, _) = items[probe] else {
                    high = middle - 1
                    continue
                }
                if start <= codePoint {
                    found = probe
                    low = probe + 1
                } else {
                    high = middle - 1
                }
            }
            guard let found, case .row(let start, _) = items[found], codePoint < start + UInt32(columns) else { return nil }
            return found
        }

        public func cellRect(item index: Int, column: Int) -> CGRect {
            CGRect(x: Self.rowHeader + CGFloat(column) * cell, y: tops[index], width: cell, height: cell)
        }
    }

    #if DEBUG
    public static func selfCheck() {
        let blocks = [Block(name: "Basic Latin", range: 0x20...0x7F), Block(name: "Arrows", range: 0x2190...0x21FF)]
        assert(find("U+2192", in: blocks) == .codePoint(0x2192) && find("0x41", in: blocks) == .codePoint(0x41))
        assert(find("→", in: blocks) == .codePoint(0x2192) && find("1f600", in: blocks) == .codePoint(0x1F600))
        assert(find("arrow", in: blocks) == .block(1) && find("cafe", in: blocks) == .codePoint(0xCAFE) && find("zzzz", in: blocks) == nil && find("  ", in: blocks) == nil)
        assert(find("U+D800", in: blocks) == nil, "a surrogate is no character")
        assert(index(containing: 0x2195, in: blocks) == 1 && index(containing: 0x10, in: blocks) == nil)
        assert(category(Unicode.Scalar(0x67)!) == "Lowercase Letter" && category(Unicode.Scalar(0x2192)!) == "Math Symbol")
        assert(js(0x41) == "\\u0041" && js(0x1F600) == "\\u{1F600}" && label(0x41) == "U+0041")
        assert(all.count > 300 && chart.blocks.count == chart.sections.count && chart.blocks.first?.name == "Basic Latin")

        let latin = Section(title: nil, range: 0x20...0x7F)
        assert(latin.masks.count == 6 && !latin.shows(0x7F) && latin.shows(0x41), "control characters left out")
        let narrow = Geometry(sections: [latin], width: 376)
        assert(narrow.columns == 8 && narrow.cell == 40.5 && narrow.items.count == 13, "eight columns, digits then twelve rows")
        let wide = Geometry(sections: [latin], width: 700)
        assert(wide.columns == 16 && wide.items.count == 7 && wide.height == Geometry.digits + 6 * wide.cell)
        assert(wide.item(at: 0) == 0 && wide.item(at: Geometry.digits + wide.cell * 1.5) == 2 && wide.item(at: wide.height) == nil)
        assert(wide.row(of: 0x41) == 3 && wide.row(of: 0x20) == 1 && wide.row(of: 0x10) == nil && wide.row(of: 0x90) == nil)
        let greek = Section(title: "Greek", range: 0x0370...0x037F)
        let unassigned = Section(title: "None", range: 0x0380...0x0383)
        let arrows = Section(title: "Arrows", range: 0x2190...0x219F)
        assert(unassigned.isEmpty)
        let titled = Geometry(sections: [greek, unassigned, arrows], width: 700)
        assert(titled.items == [.heading(section: 0), .row(start: 0x370, section: 0), .heading(section: 2), .row(start: 0x2190, section: 2)])
        assert(titled.tops[1] == Geometry.heading && titled.row(of: 0x2195) == 3 && titled.row(of: 0x375) == 1 && titled.row(of: 0x1000) == nil)
        assert(!isVisible(Unicode.Scalar(0x7F)!) && isVisible(Unicode.Scalar(0x41)!) && !isVisible(Unicode.Scalar(0x0378)!))
        assert(shown(Unicode.Scalar(0x0301)!) == "\u{25CC}\u{0301}" && shown(Unicode.Scalar(0x41)!) == "A")
    }
    #endif
}
