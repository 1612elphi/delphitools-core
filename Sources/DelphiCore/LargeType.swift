import CoreGraphics
import Foundation

public enum LargeTypeEngine {

    public enum CharClass: String, Sendable {
        case digit, space, letter, special
    }

    public static let minSize: CGFloat = 28
    public static let maxSize: CGFloat = 360
    public static let defaultSize: CGFloat = 112
    public static let sizeStep: CGFloat = 4

    public static let defaultAspect: CGFloat = 0.6

    public static let spaceGlyph = "␣"

    /// The strip lays out every cell eagerly, so the glyphs shown are capped;
    /// the character count in the controls still reports the whole string.
    public static let maxGlyphs = 400

    public static func glyphs(_ text: String) -> [Character] {
        Array(text.prefix(maxGlyphs))
    }

    public static func charClass(_ ch: Character) -> CharClass {
        if ch.isNumber { return .digit }
        if ch.isWhitespace { return .space }
        if ch.isLetter { return .letter }
        return .special
    }

    #if DEBUG
    public static func selfCheck() {
        assert(charClass("7") == .digit)
        assert(charClass(" ") == .space)
        assert(charClass("é") == .letter)
        assert(charClass("#") == .special)
        assert(glyphs(String(repeating: "x", count: maxGlyphs * 3)).count == maxGlyphs)
    }
    #endif
}

/// Where the cells go: the same grid for every glyph, rows centred in their column, columns filled in reading order.
public enum LargeTypeLayout {
    public static let cellPadding: CGFloat = 12
    public static let positionHeight: CGFloat = 18
    /// Line height of the monospaced system font, as a share of its point size.
    public static let lineHeight: CGFloat = 1.2

    public static func cell(size: CGFloat, widest: CGFloat, positions: Bool) -> CGSize {
        CGSize(width: (size * widest).rounded(.up) + cellPadding, height: (size * lineHeight).rounded(.up) + cellPadding + (positions ? positionHeight : 0))
    }

    /// Largest size in the engine's steps at which `glyphs` fit the columns without scrolling; the smallest size otherwise.
    public static func fit(_ glyphs: [Character], widest: CGFloat, widths: [CGFloat], height: CGFloat, positions: Bool) -> CGFloat {
        guard !glyphs.isEmpty, !widths.isEmpty, height > 0 else { return LargeTypeEngine.defaultSize }
        var size = LargeTypeEngine.maxSize
        while size > LargeTypeEngine.minSize {
            let cell = cell(size: size, widest: widest, positions: positions)
            let rows = Int(height / cell.height)
            let perRow = widths.map { Int($0 / cell.width) }
            if rows > 0, !perRow.contains(0), wrap(glyphs, perRow: perRow, rowsPerColumn: rows).count <= rows * widths.count { return size }
            size -= LargeTypeEngine.sizeStep
        }
        return LargeTypeEngine.minSize
    }

    /// Cells in each row, in reading order. Each column takes `rowsPerColumn` rows, the last takes the rest.
    /// A word starting mid-row moves to the next row when the next row holds it whole.
    public static func wrap(_ glyphs: [Character], perRow: [Int], rowsPerColumn: Int) -> [Int] {
        func capacity(_ row: Int) -> Int { perRow[min(row / rowsPerColumn, perRow.count - 1)] }
        var rows: [Int] = []
        var index = 0
        while index < glyphs.count {
            var end = min(index + capacity(rows.count), glyphs.count)
            if end < glyphs.count, !glyphs[end].isWhitespace, !glyphs[end - 1].isWhitespace {
                var start = end - 1
                while start > index, !glyphs[start - 1].isWhitespace { start -= 1 }
                let length = (glyphs[start...].firstIndex(where: \.isWhitespace) ?? glyphs.count) - start
                if start > index, length <= capacity(rows.count + 1) { end = start }
            }
            rows.append(end - index)
            index = end
        }
        return rows
    }

    /// Frames from a top of zero. With two columns the rows are shared as evenly as the wrap allows, the first column first.
    public static func frames(_ glyphs: [Character], size: CGFloat, widest: CGFloat, columns: [ClosedRange<CGFloat>], positions: Bool) -> [CGRect] {
        guard !glyphs.isEmpty, !columns.isEmpty else { return [] }
        let cell = cell(size: size, widest: widest, positions: positions)
        let perRow = columns.map { max(1, Int(($0.upperBound - $0.lowerBound) / cell.width)) }
        var rowsPerColumn = columns.count > 1 ? max(1, Int((Double(glyphs.count) / Double(perRow.reduce(0, +))).rounded(.up))) : Int.max
        var rows = wrap(glyphs, perRow: perRow, rowsPerColumn: rowsPerColumn)
        while rows.count > rowsPerColumn * columns.count {
            rowsPerColumn += 1
            rows = wrap(glyphs, perRow: perRow, rowsPerColumn: rowsPerColumn)
        }
        var frames: [CGRect] = []
        for (index, inRow) in rows.enumerated() {
            let column = min(index / rowsPerColumn, columns.count - 1)
            let row = index - column * rowsPerColumn
            let span = columns[column]
            let left = span.lowerBound + ((span.upperBound - span.lowerBound) - CGFloat(inRow) * cell.width) / 2
            for slot in 0..<inRow {
                frames.append(CGRect(x: left + CGFloat(slot) * cell.width, y: CGFloat(row) * cell.height, width: cell.width, height: cell.height))
            }
        }
        return frames
    }

    #if DEBUG
    public static func selfCheck() {
        let cell = cell(size: 100, widest: 0.6, positions: false)
        assert(cell == CGSize(width: 72, height: 132))
        assert(fit([], widest: 0.6, widths: [300], height: 300, positions: false) == LargeTypeEngine.defaultSize)
        assert(fit(["x"], widest: 0.6, widths: [4000], height: 4000, positions: false) == LargeTypeEngine.maxSize)
        assert(fit(Array(repeating: "x", count: 400), widest: 0.6, widths: [100], height: 100, positions: true) == LargeTypeEngine.minSize)
        let one = frames(Array("abc"), size: 100, widest: 0.6, columns: [0...720], positions: false)
        assert(one.count == 3 && one[0].minX == 252 && one.allSatisfy { $0.minY == 0 })
        let two = frames(Array("abcd"), size: 100, widest: 0.6, columns: [0...144, 200...344], positions: false)
        assert(two.map(\.minX) == [0, 72, 200, 272] && two.allSatisfy { $0.minY == 0 })
        assert(wrap(Array("ab cde"), perRow: [4], rowsPerColumn: .max) == [3, 3])
        assert(wrap(Array("abcdefg"), perRow: [4], rowsPerColumn: .max) == [4, 3])
        assert(wrap(Array("a bcdefg"), perRow: [4], rowsPerColumn: .max) == [4, 4])
        assert(wrap(Array("abcd ef"), perRow: [4], rowsPerColumn: .max) == [4, 3])
    }
    #endif
}
