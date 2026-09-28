import CoreGraphics

/// The checks drawn behind transparent pixels.
public enum Checkerboard {
    /// `rect` filled with `tones.light`, then squares of `square` in `tones.dark` on every other cell, a light cell first.
    public static func fill(_ context: CGContext, _ rect: CGRect, square: CGFloat, tones: (light: CGColor, dark: CGColor)) {
        context.setFillColor(tones.light)
        context.fill(rect)
        context.setFillColor(tones.dark)
        let side = max(square, 1)
        var row = 0
        var y = rect.minY
        while y < rect.maxY {
            var x = rect.minX + (row.isMultiple(of: 2) ? side : 0)
            while x < rect.maxX {
                context.fill(CGRect(x: x, y: y, width: side, height: side).intersection(rect))
                x += side * 2
            }
            y += side
            row += 1
        }
    }
}
