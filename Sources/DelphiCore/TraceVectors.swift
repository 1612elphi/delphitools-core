import CoreGraphics
import Foundation

/// The SVG imagetracerjs 1.2.6 writes, read back into paths: `<path fill="rgb(…)" stroke-width opacity d>` elements,
/// absolute M, L, Q and Z, layer after layer in palette order. Nothing else appears in its output with the options
/// this tool sets (no lcpr or qcpr markers).
public struct TraceVectors: @unchecked Sendable {
    public struct Layer {
        public let red: UInt8, green: UInt8, blue: UInt8
        public let opacity: CGFloat
        public let strokeWidth: CGFloat
        /// Every path of this colour, holes wound the other way, for a non-zero fill.
        public let fill: CGPath
        /// Straight segments, and quadratic curves, each as its own subpath.
        public let lines: CGPath
        public let curves: CGPath
        public let nodes: [CGPoint]
        public var paths: Int
        public var lineCount: Int
        public var curveCount: Int
    }

    public let size: CGSize
    public let layers: [Layer]

    public var paths: Int { layers.reduce(0) { $0 + $1.paths } }
    public var lineCount: Int { layers.reduce(0) { $0 + $1.lineCount } }
    public var curveCount: Int { layers.reduce(0) { $0 + $1.curveCount } }

    /// The layer colours that draw anything.
    public var palette: [DelphiColour] {
        layers.filter { $0.opacity > 0 && $0.paths > 0 }.map {
            DelphiColour(r: Double($0.red) / 255, g: Double($0.green) / 255, b: Double($0.blue) / 255)
        }
    }

    /// The paths of imagetracerjs's `svg`; nil when the root has no size.
    public static func parse(_ svg: String) -> TraceVectors? {
        guard let size = SVGMarkup.size(of: svg) else { return nil }
        struct Builder {
            var key: String
            var red: UInt8 = 0, green: UInt8 = 0, blue: UInt8 = 0
            var opacity: CGFloat = 1
            var strokeWidth: CGFloat = 0
            let fill = CGMutablePath(), lines = CGMutablePath(), curves = CGMutablePath()
            var nodes: [CGPoint] = []
            var paths = 0, lineCount = 0, curveCount = 0
        }
        var builders: [Builder] = []
        var index: [String: Int] = [:]

        for element in svg.components(separatedBy: "<path ").dropFirst() {
            guard let end = element.range(of: "/>") else { continue }
            let tag = " " + element[..<end.lowerBound]
            let tagSlice = Substring(tag)
            guard let fill = SVGMarkup.attribute("fill", in: tagSlice), let data = SVGMarkup.attribute("d", in: tagSlice) else { continue }
            // palette entries can share an RGB and differ in alpha
            let key = fill + "|" + (SVGMarkup.attribute("opacity", in: tagSlice) ?? "1")
            let slot: Int
            if let known = index[key] {
                slot = known
            } else {
                var builder = Builder(key: key)
                let rgb = fill.drop { !$0.isNumber }.split { !$0.isNumber }.compactMap { UInt8($0) }
                if rgb.count == 3 { (builder.red, builder.green, builder.blue) = (rgb[0], rgb[1], rgb[2]) }
                builder.opacity = SVGMarkup.attribute("opacity", in: tagSlice).flatMap(Double.init).map { CGFloat($0) } ?? 1
                builder.strokeWidth = SVGMarkup.attribute("stroke-width", in: tagSlice).flatMap(Double.init).map { CGFloat($0) } ?? 0
                slot = builders.count
                index[key] = slot
                builders.append(builder)
            }
            builders[slot].paths += 1

            let tokens = data.split(separator: " ")
            var at = 0
            var pen = CGPoint.zero
            func point() -> CGPoint? {
                guard at + 1 < tokens.count, let x = Double(tokens[at]), let y = Double(tokens[at + 1]) else { return nil }
                at += 2
                return CGPoint(x: x, y: y)
            }
            while at < tokens.count {
                let command = tokens[at]
                at += 1
                switch command {
                case "M":
                    guard let to = point() else { break }
                    builders[slot].fill.move(to: to)
                    builders[slot].nodes.append(to)
                    pen = to
                case "L":
                    guard let to = point() else { break }
                    builders[slot].fill.addLine(to: to)
                    builders[slot].lines.move(to: pen)
                    builders[slot].lines.addLine(to: to)
                    builders[slot].lineCount += 1
                    builders[slot].nodes.append(to)
                    pen = to
                case "Q":
                    guard let control = point(), let to = point() else { break }
                    builders[slot].fill.addQuadCurve(to: to, control: control)
                    builders[slot].curves.move(to: pen)
                    builders[slot].curves.addQuadCurve(to: to, control: control)
                    builders[slot].curveCount += 1
                    builders[slot].nodes.append(to)
                    pen = to
                case "Z":
                    builders[slot].fill.closeSubpath()
                default:
                    continue
                }
            }
        }
        let layers = builders.map {
            Layer(red: $0.red, green: $0.green, blue: $0.blue, opacity: $0.opacity, strokeWidth: $0.strokeWidth,
                  fill: $0.fill, lines: $0.lines, curves: $0.curves, nodes: $0.nodes,
                  paths: $0.paths, lineCount: $0.lineCount, curveCount: $0.curveCount)
        }
        return TraceVectors(size: size, layers: layers)
    }

    /// Colours for the outline drawing, resolved for the appearance it is drawn in.
    public struct Ink {
        public let lines: CGColor
        public let curves: CGColor
        public let wash: CGColor

        public init(lines: CGColor, curves: CGColor, wash: CGColor) {
            self.lines = lines
            self.curves = curves
            self.wash = wash
        }
    }

    /// The trace drawn at `pixels` on checks of `checks` tones: filled as a browser draws it, or with `ink` as its outlines
    /// over a washed-out fill, straight segments and curves in their own colours, a square on every node.
    public func render(pixels: CGSize, ink: Ink?, checks: (light: CGColor, dark: CGColor)) -> CGImage? {
        let width = Int(pixels.width.rounded()), height = Int(pixels.height.rounded())
        guard width > 0, height > 0, size.width > 0, size.height > 0,
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        let bounds = CGRect(x: 0, y: 0, width: width, height: height)
        Checkerboard.fill(context, bounds, square: CGFloat(max(width, height)) / 48, tones: checks)

        let scale = CGSize(width: CGFloat(width) / size.width, height: CGFloat(height) / size.height)
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: scale.width, y: -scale.height)
        context.setLineJoin(.miter)
        context.setMiterLimit(4)
        for layer in layers where layer.opacity > 0 {
            let colour = CGColor(srgbRed: CGFloat(layer.red) / 255, green: CGFloat(layer.green) / 255, blue: CGFloat(layer.blue) / 255, alpha: 1)
            context.setAlpha(layer.opacity)
            context.setFillColor(colour)
            context.addPath(layer.fill)
            context.fillPath(using: .winding)
            if layer.strokeWidth > 0 {
                context.setStrokeColor(colour)
                context.setLineWidth(layer.strokeWidth)
                context.addPath(layer.fill)
                context.strokePath()
            }
        }
        context.setAlpha(1)
        guard let ink else { return context.makeImage() }

        context.saveGState()
        context.concatenate(context.ctm.inverted())
        context.setFillColor(ink.wash)
        context.fill(bounds)
        context.restoreGState()

        // ~1.5 device px
        let pixel = CGFloat(max(width, height)) / 500
        let unit = pixel / max(scale.width, scale.height)
        context.setLineWidth(unit)
        context.setLineJoin(.round)
        for (paths, colour) in [(layers.map(\.lines), ink.lines), (layers.map(\.curves), ink.curves)] {
            context.setStrokeColor(colour)
            paths.forEach(context.addPath)
            context.strokePath()
        }
        let node = unit * 2.5
        context.setFillColor(ink.lines)
        for layer in layers {
            context.addRects(layer.nodes.map { CGRect(x: $0.x - node / 2, y: $0.y - node / 2, width: node, height: node) })
        }
        context.fillPath()
        return context.makeImage()
    }
}
