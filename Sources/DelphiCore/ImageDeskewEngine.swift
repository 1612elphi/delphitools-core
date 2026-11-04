import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import Vision

/// Corner order is clockwise from the top left, as the web tool's `Quad`.
public enum DeskewCorner: Int, CaseIterable, Identifiable, Sendable {
    case topLeft, topRight, bottomRight, bottomLeft

    public var id: Int { rawValue }

    public var label: String {
        switch self {
        case .topLeft: String(localized: "Top left")
        case .topRight: String(localized: "Top right")
        case .bottomRight: String(localized: "Bottom right")
        case .bottomLeft: String(localized: "Bottom left")
        }
    }
}

public struct DeskewAspect: Identifiable, Hashable, Sendable {
    public let label: String
    /// Long-to-short ratio; nil keeps the quad's own proportions.
    public let ratio: Double?

    public var id: String { label }

    public static let all: [DeskewAspect] = [
        DeskewAspect(label: String(localized: "Auto"), ratio: nil),
        DeskewAspect(label: "A4", ratio: 2.0.squareRoot()),
        DeskewAspect(label: String(localized: "Letter"), ratio: 11 / 8.5),
        DeskewAspect(label: "1:1", ratio: 1),
        DeskewAspect(label: "4:3", ratio: 4 / 3),
        DeskewAspect(label: "3:2", ratio: 3 / 2),
        DeskewAspect(label: "16:9", ratio: 16 / 9),
    ]
}

public enum ImageDeskewEngine {

    /// A starting quad `inset` in from each side of a `width` × `height` image, clockwise from the top left.
    public static func insetQuad(width: Double, height: Double, inset: Double = 0.12) -> [CGPoint] {
        let dx = width * inset
        let dy = height * inset
        return [
            CGPoint(x: dx, y: dy),
            CGPoint(x: width - dx, y: dy),
            CGPoint(x: width - dx, y: height - dy),
            CGPoint(x: dx, y: height - dy),
        ]
    }

    /// Output size for `quad`: the longer of each pair of opposite edges.
    public static func outputSize(quad: [CGPoint]) -> CGSize {
        guard quad.count == 4 else { return CGSize(width: 1, height: 1) }
        let (tl, tr, br, bl) = (quad[0], quad[1], quad[2], quad[3])
        return CGSize(
            width: max(1, (max(distance(tl, tr), distance(bl, br))).rounded()),
            height: max(1, (max(distance(tl, bl), distance(tr, br))).rounded())
        )
    }

    /// `size` at `ratio`, long side over short, keeping its long side; a nil ratio keeps `size`.
    public static func fitAspect(_ size: CGSize, ratio: Double?) -> CGSize {
        guard let ratio, ratio > 0 else { return size }
        if size.width >= size.height {
            return CGSize(width: size.width, height: max(1, (size.width / ratio).rounded()))
        }
        return CGSize(width: max(1, (size.height / ratio).rounded()), height: size.height)
    }

    /// Longest output edge; a 48 MP sensor is 8064 px wide.
    public static let maxEdge = 8192.0

    /// `size` scaled down so no side exceeds `maxEdge`.
    public static func capped(_ size: CGSize, maxEdge: Double = maxEdge) -> CGSize {
        let scale = min(1, maxEdge / max(size.width, size.height, 1))
        return CGSize(width: max(1, (size.width * scale).rounded()), height: max(1, (size.height * scale).rounded()))
    }

    /// True for a convex quad wound clockwise in top-left coordinates; a bow-tie,
    /// mirrored or collapsed quad has no perspective correction.
    public static func isConvex(_ quad: [CGPoint]) -> Bool {
        guard quad.count == 4 else { return false }
        return (0..<4).allSatisfy { i in
            let a = quad[i], b = quad[(i + 1) % 4], c = quad[(i + 2) % 4]
            return (b.x - a.x) * (c.y - b.y) - (b.y - a.y) * (c.x - b.x) > 1e-6
        }
    }

    /// Perspective-corrects `image` through `quad` (top-left origin, image
    /// pixels) and scales the result to `size`.
    public static func correct(_ image: CIImage, quad: [CGPoint], to size: CGSize) -> CIImage? {
        guard isConvex(quad), size.width >= 1, size.height >= 1 else { return nil }
        let extent = image.extent
        let flipped = quad.map { CGPoint(x: extent.minX + $0.x, y: extent.maxY - $0.y) }

        let filter = CIFilter.perspectiveCorrection()
        filter.inputImage = image
        filter.topLeft = flipped[0]
        filter.topRight = flipped[1]
        filter.bottomRight = flipped[2]
        filter.bottomLeft = flipped[3]
        filter.crop = true
        guard let corrected = filter.outputImage, corrected.extent.width > 0, corrected.extent.height > 0 else {
            return nil
        }

        let transform = CGAffineTransform(
            scaleX: size.width / corrected.extent.width,
            y: size.height / corrected.extent.height
        )
        return corrected.transformed(by: transform)
    }

    /// Seeds the quad from the largest rectangle Vision finds, as unit-square
    /// points with a top-left origin.
    public static func detectQuad(in image: CIImage) -> [CGPoint]? {
        let request = VNDetectRectanglesRequest()
        request.maximumObservations = 1
        request.minimumConfidence = 0.6
        request.minimumAspectRatio = 0.2
        request.quadratureTolerance = 30

        let handler = VNImageRequestHandler(ciImage: image, options: [:])
        guard (try? handler.perform([request])) != nil,
              let rectangle = request.results?.first
        else { return nil }

        // vision origin is bottom-left
        let quad = [rectangle.topLeft, rectangle.topRight, rectangle.bottomRight, rectangle.bottomLeft]
            .map { CGPoint(x: $0.x, y: 1 - $0.y) }
        return isConvex(quad) ? quad : nil
    }

    /// The point at (u, v) of the unit square under the projective map that takes the square's corners to `quad`
    /// (Heckbert 1989, square to quad). A line of the output is a straight line of the quad, foreshortened.
    public static func project(_ u: Double, _ v: Double, into quad: [CGPoint]) -> CGPoint {
        guard quad.count == 4 else { return .zero }
        let (p0, p1, p2, p3) = (quad[0], quad[1], quad[2], quad[3])
        let sx = p0.x - p1.x + p2.x - p3.x
        let sy = p0.y - p1.y + p2.y - p3.y
        let (dx1, dx2, dy1, dy2) = (p1.x - p2.x, p3.x - p2.x, p1.y - p2.y, p3.y - p2.y)
        let den = dx1 * dy2 - dx2 * dy1
        let (g, h) = abs(den) < 1e-9 ? (0.0, 0.0) : ((sx * dy2 - dx2 * sy) / den, (dx1 * sy - sx * dy1) / den)
        let a = p1.x - p0.x + g * p1.x, b = p3.x - p0.x + h * p3.x
        let d = p1.y - p0.y + g * p1.y, e = p3.y - p0.y + h * p3.y
        let w = g * u + h * v + 1
        return CGPoint(x: (a * u + b * v + p0.x) / w, y: (d * u + e * v + p0.y) / w)
    }

    private static func distance(_ a: CGPoint, _ b: CGPoint) -> Double {
        hypot(b.x - a.x, b.y - a.y)
    }
}

/// What a pointer at a point takes hold of on a quad: a corner, an edge (two corners) or the whole quad.
public enum DeskewGrab: Equatable, Sendable {
    case corner(Int)
    case edge(Int)
    case whole

    /// Reach in points.
    public static let reach = (corner: 30.0, edge: 18.0)

    public static func at(_ point: CGPoint, in quad: [CGPoint]) -> DeskewGrab? {
        guard quad.count == 4 else { return nil }
        let nearest = quad.indices.min { hypot(quad[$0].x - point.x, quad[$0].y - point.y) < hypot(quad[$1].x - point.x, quad[$1].y - point.y) }!
        if hypot(quad[nearest].x - point.x, quad[nearest].y - point.y) <= reach.corner { return .corner(nearest) }
        let distances = (0..<4).map { distance(from: point, to: quad[$0], quad[($0 + 1) % 4]) }
        if let edge = distances.indices.min(by: { distances[$0] < distances[$1] }), distances[edge] <= reach.edge { return .edge(edge) }
        return polygon(quad).contains(point) ? .whole : nil
    }

    /// `quad` with the grabbed corners moved by `delta`, held inside `size` together.
    public static func move(_ quad: [CGPoint], _ grab: DeskewGrab, by delta: CGPoint, within size: CGSize) -> [CGPoint] {
        let moving = switch grab {
        case .corner(let index): [index]
        case .edge(let index): [index, (index + 1) % 4]
        case .whole: [0, 1, 2, 3]
        }
        var (dx, dy) = (delta.x, delta.y)
        for index in moving {
            dx = min(max(dx, -quad[index].x), size.width - quad[index].x)
            dy = min(max(dy, -quad[index].y), size.height - quad[index].y)
        }
        var moved = quad
        for index in moving { moved[index] = CGPoint(x: quad[index].x + dx, y: quad[index].y + dy) }
        return moved
    }

    public static func polygon(_ points: [CGPoint]) -> CGPath {
        let path = CGMutablePath()
        guard let first = points.first else { return path }
        path.move(to: first)
        points.dropFirst().forEach { path.addLine(to: $0) }
        path.closeSubpath()
        return path
    }

    /// Lines through the quad at each `1/divisions` of its sides, foreshortened as the output will be.
    public static func grid(through quad: [CGPoint], divisions: Int) -> CGPath {
        let path = CGMutablePath()
        guard quad.count == 4, divisions > 1 else { return path }
        for step in 1..<divisions {
            let share = Double(step) / Double(divisions)
            path.move(to: ImageDeskewEngine.project(share, 0, into: quad))
            path.addLine(to: ImageDeskewEngine.project(share, 1, into: quad))
            path.move(to: ImageDeskewEngine.project(0, share, into: quad))
            path.addLine(to: ImageDeskewEngine.project(1, share, into: quad))
        }
        return path
    }

    private static func distance(from point: CGPoint, to a: CGPoint, _ b: CGPoint) -> Double {
        let (dx, dy) = (b.x - a.x, b.y - a.y)
        let length = dx * dx + dy * dy
        let t = length > 0 ? min(max(((point.x - a.x) * dx + (point.y - a.y) * dy) / length, 0), 1) : 0
        return hypot(point.x - (a.x + t * dx), point.y - (a.y + t * dy))
    }

    #if DEBUG
    public static func selfCheck() {
        let square = [CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0), CGPoint(x: 100, y: 100), CGPoint(x: 0, y: 100)]
        assert(at(CGPoint(x: 10, y: 12), in: square) == .corner(0))
        assert(at(CGPoint(x: 95, y: 104), in: square) == .corner(2))
        assert(at(CGPoint(x: 50, y: -8), in: square) == .edge(0))
        assert(at(CGPoint(x: 108, y: 50), in: square) == .edge(1))
        assert(at(CGPoint(x: 50, y: 50), in: square) == .whole)
        assert(at(CGPoint(x: 200, y: 200), in: square) == nil)
        let size = CGSize(width: 120, height: 120)
        assert(move(square, .corner(2), by: CGPoint(x: 50, y: 5), within: size)[2] == CGPoint(x: 120, y: 105))
        let edge = move(square, .edge(3), by: CGPoint(x: -5, y: 10), within: size)
        assert(edge[3] == CGPoint(x: 0, y: 110) && edge[0] == CGPoint(x: 0, y: 10) && edge[1] == square[1])
        assert(move(square, .whole, by: CGPoint(x: 30, y: -3), within: size) == square.map { CGPoint(x: $0.x + 20, y: $0.y) })
        let skewed = [CGPoint(x: 20, y: 10), CGPoint(x: 190, y: 5), CGPoint(x: 180, y: 95), CGPoint(x: 10, y: 80)]
        for (corner, unit) in zip(skewed, [(0.0, 0.0), (1.0, 0.0), (1.0, 1.0), (0.0, 1.0)]) {
            let point = ImageDeskewEngine.project(unit.0, unit.1, into: skewed)
            assert(abs(point.x - corner.x) < 1e-9 && abs(point.y - corner.y) < 1e-9)
        }
        let middle = ImageDeskewEngine.project(0.5, 0.5, into: square)
        assert(abs(middle.x - 50) < 1e-9 && abs(middle.y - 50) < 1e-9)
    }
    #endif
}
