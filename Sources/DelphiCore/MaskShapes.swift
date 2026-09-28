import CoreGraphics
import Foundation

// cgpath is immutable
public struct MaskShape: Identifiable, @unchecked Sendable {
    public let id: String
    public let path: CGPath
}

/// Procedural mask library ported from the web tool's `mask-shapes.ts`:
/// 28 families × 12 variants, laid out in a 0…100 box.
public enum MaskShapes {

    public static let variants = 12

    public static let all: [MaskShape] = build()

    public static let `default`: MaskShape = all.first { $0.id == "squircle-4" } ?? all[0]

    // web declaration order
    public static let familyNames: [String] = families.map(\.name)

    private static let c = 100.0 / 2
    private static let r = 46.0
    private static let tau = Double.pi * 2
    private static let arc = 96

    private static func polar(_ angle: Double, _ radius: Double, _ cx: Double = c, _ cy: Double = c) -> CGPoint {
        CGPoint(x: cx + radius * cos(angle), y: cy + radius * sin(angle))
    }

    private static func ring(
        _ n: Int,
        _ radius: (Int) -> Double,
        start: Double = -.pi / 2,
        cx: Double = c,
        cy: Double = c
    ) -> [CGPoint] {
        (0..<n).map { polar(start + (Double($0) / Double(n)) * tau, radius($0), cx, cy) }
    }

    private static func sample(_ n: Int, _ at: (Double) -> CGPoint) -> [CGPoint] {
        (0..<n).map { at((Double($0) / Double(n)) * tau) }
    }

    private static func rotate(_ points: [CGPoint], turns: Double) -> [CGPoint] {
        let cosine = cos(turns * tau)
        let sine = sin(turns * tau)
        return points.map {
            CGPoint(
                x: c + ($0.x - c) * cosine - ($0.y - c) * sine,
                y: c + ($0.x - c) * sine + ($0.y - c) * cosine
            )
        }
    }

    // one factor keeps proportions
    private static func fit(_ parts: [[CGPoint]]) -> [[CGPoint]] {
        let reach = parts.flatMap { $0 }.map { hypot($0.x - c, $0.y - c) }.max() ?? 0
        guard reach > 0 else { return parts }
        let k = min(1, r / reach)
        return parts.map { $0.map { CGPoint(x: c + ($0.x - c) * k, y: c + ($0.y - c) * k) } }
    }

    private static func poly(_ parts: [[CGPoint]]) -> CGPath {
        let path = CGMutablePath()
        for points in parts where points.count > 1 {
            path.addLines(between: points)
            path.closeSubpath()
        }
        return path
    }

    // catmull-rom to cubics
    private static func smooth(_ parts: [[CGPoint]]) -> CGPath {
        let path = CGMutablePath()
        for points in parts where points.count > 2 {
            let n = points.count
            let at = { (i: Int) in points[((i % n) + n) % n] }
            path.move(to: at(0))
            for i in 0..<n {
                let p0 = at(i - 1), p1 = at(i), p2 = at(i + 1), p3 = at(i + 2)
                let c1 = CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6)
                let c2 = CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6)
                path.addCurve(to: p2, control1: c1, control2: c2)
            }
            path.closeSubpath()
        }
        return path
    }

    private static func spin(_ turns: Double, _ parts: [[CGPoint]]) -> CGPath {
        poly(fit(parts.map { rotate($0, turns: turns) }))
    }

    // clockwise, safe at zero
    private static func rrect(_ x: Double, _ y: Double, _ w: Double, _ h: Double, _ radius: Double) -> [CGPoint] {
        let corners: [(Double, Double, Double)] = [
            (x + w - radius, y + radius, -0.25),
            (x + w - radius, y + h - radius, 0),
            (x + radius, y + h - radius, 0.25),
            (x + radius, y + radius, 0.5),
        ]
        return corners.flatMap { cx, cy, start in
            (0...12).map { polar((start + (Double($0) / 12) * 0.25) * tau, radius, cx, cy) }
        }
    }

    private static func count(_ rnd: MaskRandom, _ from: Int, _ span: Int) -> Int {
        from + Int(rnd.next() * Double(span))
    }

    private static let heart: [CGPoint] = sample(arc) { t in
        let s = r / 17
        return CGPoint(
            x: c + 16 * pow(sin(t), 3) * s,
            y: c - (13 * cos(t) - 5 * cos(2 * t) - 2 * cos(3 * t) - cos(4 * t) + 2) * s
        )
    }

    private static let drop: [CGPoint] = {
        let radius = 0.68 * r
        let cy = c + r - radius
        let beta = acos(radius / (2 * r - radius))
        let from = -Double.pi / 2 + beta
        let sweep = tau - 2 * beta
        return [CGPoint(x: c, y: c - r)]
            + (0...64).map { polar(from + (Double($0) / 64) * sweep, radius, c, cy) }
    }()

    private static let leaf: [CGPoint] = sample(arc) { t in
        CGPoint(
            x: c + r * cos(t),
            y: c + 0.58 * r * (sin(t) < 0 ? -1 : 1) * pow(abs(sin(t)), 1.7)
        )
    }

    private static let egg: [CGPoint] = sample(arc) { t in
        CGPoint(x: c + 0.78 * r * cos(t) * (1 + 0.18 * sin(t)), y: c + 0.95 * r * sin(t))
    }

    private static let arrow: [CGPoint] = [
        CGPoint(x: c - r, y: c - 0.22 * r),
        CGPoint(x: c + 0.1 * r, y: c - 0.22 * r),
        CGPoint(x: c + 0.1 * r, y: c - 0.55 * r),
        CGPoint(x: c + r, y: c),
        CGPoint(x: c + 0.1 * r, y: c + 0.55 * r),
        CGPoint(x: c + 0.1 * r, y: c + 0.22 * r),
        CGPoint(x: c - r, y: c + 0.22 * r),
    ]

    private static let bolt: [CGPoint] = [
        CGPoint(x: 56, y: 4), CGPoint(x: 24, y: 56), CGPoint(x: 45, y: 56), CGPoint(x: 40, y: 96),
        CGPoint(x: 76, y: 44), CGPoint(x: 55, y: 44), CGPoint(x: 62, y: 4),
    ]

    private static let bubbleBody: [CGPoint] = rrect(c - r, c - r, 2 * r, 1.5 * r, 0.3 * r)

    private static let bubbleTail: [CGPoint] = [
        CGPoint(x: c - 0.35 * r, y: c + 0.3 * r),
        CGPoint(x: c + 0.05 * r, y: c + 0.3 * r),
        CGPoint(x: c - 0.55 * r, y: c + r),
    ]

    private static func cross(_ a: Double) -> [CGPoint] {
        [
            CGPoint(x: c - a, y: c - r), CGPoint(x: c + a, y: c - r),
            CGPoint(x: c + a, y: c - a), CGPoint(x: c + r, y: c - a),
            CGPoint(x: c + r, y: c + a), CGPoint(x: c + a, y: c + a),
            CGPoint(x: c + a, y: c + r), CGPoint(x: c - a, y: c + r),
            CGPoint(x: c - a, y: c + a), CGPoint(x: c - r, y: c + a),
            CGPoint(x: c - r, y: c - a), CGPoint(x: c - a, y: c - a),
        ]
    }

    private static func gear(_ n: Int) -> [CGPoint] {
        let step = tau / Double(n)
        return (0..<n).flatMap { k -> [CGPoint] in
            let a = Double(k) * step - .pi / 2
            return [
                polar(a - 0.3 * step, 0.76 * r),
                polar(a - 0.17 * step, r),
                polar(a + 0.17 * step, r),
                polar(a + 0.3 * step, 0.76 * r),
            ]
        }
    }

    private static func pie(_ turns: Double) -> [CGPoint] {
        [CGPoint(x: c, y: c)] + (0...64).map { polar(-Double.pi / 2 + (Double($0) / 64) * turns * tau, r) }
    }

    // disc minus shifted copy
    private static func moon(_ d: Double) -> [CGPoint] {
        let phi = acos(d / (2 * r))
        let outer = (0...64).map { polar(phi + (Double($0) / 64) * (tau - 2 * phi), r) }
        let inner = (0...64).map { polar(Double.pi + phi - (Double($0) / 64) * 2 * phi, r, c + d) }
        return outer + inner
    }

    private static func jittered(
        _ rnd: MaskRandom,
        _ n: Int,
        _ radius: (Int) -> Double,
        jitter: Double = 0.5
    ) -> [CGPoint] {
        let start = rnd.next() * tau
        return (0..<n).map { k in
            let angle = start + ((Double(k) + (rnd.next() - 0.5) * jitter) / Double(n)) * tau
            return polar(angle, radius(k))
        }
    }

    private static func blob(_ rnd: MaskRandom, lobes: Int, floor: Double) -> [CGPoint] {
        jittered(rnd, lobes, { _ in r * (floor + (1 - floor) * rnd.next()) })
    }

    private static func splat(_ rnd: MaskRandom) -> [CGPoint] {
        let n = 2 * count(rnd, 5, 5)
        return jittered(rnd, n, { k in
            k % 2 != 0 ? r * (0.5 + 0.2 * rnd.next()) : r * (0.85 + 0.15 * rnd.next())
        })
    }

    private static func shard(_ rnd: MaskRandom) -> [CGPoint] {
        let n = count(rnd, 4, 4)
        return jittered(rnd, n, { _ in r * (0.7 + 0.3 * rnd.next()) }, jitter: 0.6)
    }

    // bites go inward
    private static func torn(_ rnd: MaskRandom) -> [CGPoint] {
        let a = 0.92 * r
        let b = a * (0.65 + 0.35 * rnd.next())
        func edge(_ from: CGPoint, _ to: CGPoint, _ nx: Double, _ ny: Double) -> [CGPoint] {
            (0..<10).map { k in
                let t = Double(k) / 10
                let bite = rnd.next() * 0.12 * r
                return CGPoint(
                    x: from.x + (to.x - from.x) * t + nx * bite,
                    y: from.y + (to.y - from.y) * t + ny * bite
                )
            }
        }
        return edge(CGPoint(x: c - a, y: c - b), CGPoint(x: c + a, y: c - b), 0, 1)
            + edge(CGPoint(x: c + a, y: c - b), CGPoint(x: c + a, y: c + b), -1, 0)
            + edge(CGPoint(x: c + a, y: c + b), CGPoint(x: c - a, y: c + b), 0, -1)
            + edge(CGPoint(x: c - a, y: c + b), CGPoint(x: c - a, y: c - b), 1, 0)
    }

    private static func cloud(_ rnd: MaskRandom) -> [[CGPoint]] {
        let puffs = count(rnd, 3, 3)
        var parts: [[CGPoint]] = [rrect(c - 0.75 * r, c + 0.1 * r, 1.5 * r, 0.4 * r, 0.2 * r)]
        for k in 0..<puffs {
            let cx = c + (Double(k) / Double(puffs - 1) - 0.5) * 1.1 * r
            let cy = c + (0.1 - 0.15 * rnd.next()) * r
            let big = k == puffs / 2 ? 0.5 : 0.3 + 0.15 * rnd.next()
            let radius = min(r * big, r - hypot(cx - c, cy - c))
            parts.append(ring(48, { _ in radius }, start: 0, cx: cx, cy: cy))
        }
        return parts
    }

    // holes inside radius floor
    private static func puddle(_ rnd: MaskRandom) -> [[CGPoint]] {
        let lobes = count(rnd, 6, 4)
        var parts: [[CGPoint]] = [blob(rnd, lobes: lobes, floor: 0.62)]
        for _ in 0..<count(rnd, 1, 3) {
            let angle = rnd.next() * tau
            let centre = polar(angle, rnd.next() * 0.22 * r)
            let n = count(rnd, 5, 3)
            let start = rnd.next() * tau
            parts.append(Array(ring(n, { _ in r * (0.12 + 0.12 * rnd.next()) }, start: start, cx: centre.x, cy: centre.y).reversed()))
        }
        return parts
    }

    private static func pixel(_ rnd: MaskRandom) -> [[CGPoint]] {
        let n = 9
        let cell = (2 * r) / Double(n)
        let radii = (0..<7).map { _ in 0.55 + 0.45 * rnd.next() }
        let start = rnd.next() * tau
        func radius(at angle: Double) -> Double {
            let u = (((angle - start) / tau).truncatingRemainder(dividingBy: 1) + 1).truncatingRemainder(dividingBy: 1)
            let k = Int(u * Double(radii.count))
            let f = u * Double(radii.count) - Double(k)
            return r * (radii[k % radii.count] * (1 - f) + radii[(k + 1) % radii.count] * f)
        }
        var squares: [[CGPoint]] = []
        for gy in 0..<n {
            for gx in 0..<n {
                let x = c - r + Double(gx) * cell
                let y = c - r + Double(gy) * cell
                let mx = x + cell / 2 - c
                let my = y + cell / 2 - c
                if hypot(mx, my) < radius(at: atan2(my, mx)) {
                    squares.append([
                        CGPoint(x: x, y: y), CGPoint(x: x + cell, y: y),
                        CGPoint(x: x + cell, y: y + cell), CGPoint(x: x, y: y + cell),
                    ])
                }
            }
        }
        return squares
    }

    private typealias Family = (name: String, make: @Sendable (Int, Double, MaskRandom) -> CGPath)

    private static let families: [Family] = [
        ("polygon", { i, _, _ in poly([ring(i + 3, { _ in r })]) }),
        ("squircle", { i, _, _ in
            let p = 2 + Double(i) * 1.5
            let f = { (v: Double) in (v < 0 ? -1.0 : 1.0) * pow(abs(v), 2 / p) }
            return poly([sample(arc) { a in CGPoint(x: c + r * f(cos(a)), y: c + r * f(sin(a))) }])
        }),
        ("rounded", { _, t, _ in poly([rrect(c - r, c - r, 2 * r, 2 * r, t * r)]) }),
        ("pill", { _, t, _ in
            let h = 2 * r * (1 - 0.7 * t)
            return poly([rrect(c - r, c - h / 2, 2 * r, h, h / 2)])
        }),
        ("star", { i, _, _ in poly([ring(2 * (i + 3), { $0 % 2 != 0 ? 0.5 * r : r })]) }),
        ("burst", { i, _, _ in poly([ring(2 * (8 + 2 * i), { $0 % 2 != 0 ? 0.8 * r : r })]) }),
        ("crown", { _, _, rnd in
            let n = 2 * count(rnd, 8, 7)
            return poly([jittered(rnd, n, { $0 % 2 != 0 ? r * (0.6 + 0.25 * rnd.next()) : r }, jitter: 0.3)])
        }),
        ("flower", { i, _, _ in smooth([ring(2 * (i + 3), { $0 % 2 != 0 ? 0.6 * r : r })]) }),
        ("seal", { i, _, _ in smooth([ring(2 * (8 + i), { $0 % 2 != 0 ? 0.86 * r : r })]) }),
        ("gear", { i, _, _ in poly([gear(5 + i), Array(ring(48, { _ in 0.3 * r }).reversed())]) }),
        ("cross", { _, t, _ in poly([cross(r * (0.12 + 0.63 * t))]) }),
        ("ring", { _, t, _ in poly([ring(arc, { _ in r }), Array(ring(arc, { _ in 0.78 * r * t }).reversed())]) }),
        ("pie", { _, t, _ in poly([pie(0.25 + 0.7 * t)]) }),
        ("moon", { _, t, _ in poly([moon(2 * r * (0.35 + 0.6 * t))]) }),
        ("blob", { _, _, rnd in
            let lobes = count(rnd, 5, 4)
            return smooth([blob(rnd, lobes: lobes, floor: 0.62)])
        }),
        ("splat", { _, _, rnd in smooth([splat(rnd)]) }),
        ("puddle", { _, _, rnd in smooth(puddle(rnd)) }),
        ("cloud", { _, _, rnd in poly(cloud(rnd)) }),
        ("shard", { _, _, rnd in poly([shard(rnd)]) }),
        ("torn", { _, _, rnd in poly([torn(rnd)]) }),
        ("pixel", { _, _, rnd in poly(pixel(rnd)) }),
        ("heart", { i, _, _ in spin(Double(i) / Double(variants), [heart]) }),
        ("drop", { i, _, _ in spin(Double(i) / Double(variants), [drop]) }),
        ("leaf", { i, _, _ in spin(Double(i) / Double(variants) + 1.0 / 8, [leaf]) }),
        ("egg", { i, _, _ in spin(Double(i) / Double(variants), [egg]) }),
        ("arrow", { i, _, _ in spin(Double(i) / Double(variants), [arrow]) }),
        ("bolt", { i, _, _ in spin(Double(i) / Double(variants), [bolt]) }),
        ("bubble", { i, _, _ in spin(Double(i) / Double(variants), [bubbleBody, bubbleTail]) }),
    ]

    private static func build() -> [MaskShape] {
        var shapes: [MaskShape] = []
        for (f, family) in families.enumerated() {
            for i in 0..<variants {
                let rnd = MaskRandom(seed: f * 131 + i * 7 + 1)
                shapes.append(MaskShape(
                    id: "\(family.name)-\(i + 1)",
                    path: family.make(i, Double(i) / Double(variants - 1), rnd)
                ))
            }
        }
        // shuffle as the web
        let rnd = MaskRandom(seed: 7)
        for i in stride(from: shapes.count - 1, to: 0, by: -1) {
            shapes.swapAt(i, Int(rnd.next() * Double(i + 1)))
        }
        return shapes
    }
}

/// mulberry32, matching the web tool's seeded PRNG bit for bit.
public final class MaskRandom {
    private var state: UInt32

    public init(seed: Int) {
        state = UInt32(truncatingIfNeeded: seed)
    }

    /// The next value in 0..<1.
    public func next() -> Double {
        state = state &+ 0x6d2b_79f5
        var t = (state ^ (state >> 15)) &* (1 | state)
        t = (t &+ ((t ^ (t >> 7)) &* (61 | t))) ^ t
        return Double(t ^ (t >> 14)) / 4_294_967_296
    }
}
