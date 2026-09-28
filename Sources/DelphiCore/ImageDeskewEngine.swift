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
