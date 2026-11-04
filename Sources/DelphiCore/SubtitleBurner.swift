import AVFoundation
import CoreGraphics
import CoreImage
import CoreText
import Foundation

/// How burnt-in subtitles look: font, size and width as shares of the frame, fill and backing colours, placement.
public struct SubtitleBurnStyle: Hashable, Sendable {
    public enum FontChoice: String, CaseIterable, Sendable {
        case sans, serif, mono, rounded
        public var label: String { rawValue.capitalized }
    }

    public enum TextStyle: String, CaseIterable, Sendable {
        case outline, box, shadow, plain
        public var label: String { rawValue.capitalized }
    }

    public var font = FontChoice.sans
    public var bold = false
    /// fraction of frame height
    public var size = 0.05
    /// fraction of frame width
    public var width = 0.9
    public var red = 1.0
    public var green = 1.0
    public var blue = 1.0
    public var text = TextStyle.outline
    /// outline, box, shadow colour
    public var backingRed = 0.0
    public var backingGreen = 0.0
    public var backingBlue = 0.0
    /// fraction of frame width, from centre
    public var x = 0.0
    /// fraction of frame height, from the default baseline
    public var y = 0.0

    public static let xRange = -0.45...0.45
    public static let yRange = -0.9...0.05
    public static let sizeRange = 0.02...0.14
    public static let widthRange = 0.3...0.9

    public init() {}
}

/// Draws one cue's text as a picture the size of its lines, through Core Text so it runs on any thread.
public enum SubtitleBurnRenderer {
    private static let lineHeight = 1.25
    /// fraction from frame top
    public static let baseline = 0.94

    /// top half stacks downward
    public static func growsDown(y: Double) -> Bool { baseline + y < 0.5 }

    public static func font(_ choice: SubtitleBurnStyle.FontChoice, bold: Bool, size: CGFloat) -> CTFont {
        let name: String = switch choice {
        case .sans: bold ? "HelveticaNeue-Bold" : "HelveticaNeue"
        case .serif: bold ? "Georgia-Bold" : "Georgia"
        case .mono: bold ? "Menlo-Bold" : "Menlo-Regular"
        case .rounded: "ArialRoundedMTBold"
        }
        return CTFontCreateWithName(name as CFString, size, nil)
    }

    public static func wrap(_ text: String, maxWidth: CGFloat, width: (String) -> CGFloat) -> [String] {
        var out: [String] = []
        for raw in text.components(separatedBy: "\n") {
            var line = ""
            for word in raw.split(whereSeparator: \.isWhitespace) {
                let next = line.isEmpty ? String(word) : "\(line) \(word)"
                if !line.isEmpty, width(next) > maxWidth {
                    out.append(line)
                    line = String(word)
                } else {
                    line = next
                }
            }
            if !line.isEmpty { out.append(line) }
        }
        return out
    }

    private static func line(_ text: String, font: CTFont, colour: CGColor, stroke: CGFloat? = nil) -> CTLine {
        var attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): colour,
        ]
        if let stroke {
            // positive width: stroke only
            attributes[NSAttributedString.Key(kCTStrokeWidthAttributeName as String)] = stroke
            attributes[NSAttributedString.Key(kCTStrokeColorAttributeName as String)] = colour
        }
        return CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
    }

    /// The picture and where it sits, in top-left pixels of `frame`.
    public static func bitmap(text: String, frame: CGSize, style: SubtitleBurnStyle) -> (image: CGImage, rect: CGRect)? {
        let px = max(8, (style.size * frame.height).rounded())
        let font = font(style.font, bold: style.bold, size: px)
        let fill = CGColor(red: style.red, green: style.green, blue: style.blue, alpha: 1)
        let backing = CGColor(red: style.backingRed, green: style.backingGreen, blue: style.backingBlue, alpha: 1)
        let measure: (String) -> CGFloat = { CGFloat(CTLineGetTypographicBounds(line($0, font: font, colour: fill), nil, nil, nil)) }
        let lines = wrap(SubtitleCodec.stripTags(text), maxWidth: frame.width * style.width, width: measure)
        guard !lines.isEmpty else { return nil }

        let lineAdvance = px * lineHeight
        let centreX = frame.width / 2 + style.x * frame.width
        let bottom = frame.height * baseline + style.y * frame.height
        let padX = px * 0.3
        let padY = px * 0.15
        let stroke = style.text == .outline ? max(2, px / 8) : 0
        let shadow = style.text == .shadow ? px * 0.08 : 0
        let down = growsDown(y: style.y)
        let rows = lines.enumerated().map { index, line -> (text: String, baseline: CGFloat, width: CGFloat) in
            (line, down ? bottom + CGFloat(index) * lineAdvance : bottom - CGFloat(lines.count - 1 - index) * lineAdvance, measure(line))
        }
        let boxes = rows.map {
            CGRect(x: centreX - $0.width / 2 - padX, y: $0.baseline - px * 0.85 - padY, width: $0.width + padX * 2, height: px * 1.1 + padY * 2)
        }
        // ascenders, stroke, shadow overhang
        let bounds = boxes.dropFirst().reduce(boxes[0]) { $0.union($1) }
            .insetBy(dx: -(stroke + shadow * 3), dy: -(stroke + shadow * 3 + px * 0.3)).integral
        guard bounds.width > 0, bounds.height > 0,
              let context = CGContext(data: nil, width: Int(bounds.width), height: Int(bounds.height), bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        // top-left pixels, glyphs upright
        context.translateBy(x: -bounds.minX, y: bounds.maxY)
        context.scaleBy(x: 1, y: -1)
        context.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        context.setLineJoin(.round)
        for (row, box) in zip(rows, boxes) {
            let origin = CGPoint(x: centreX - row.width / 2, y: row.baseline)
            if style.text == .box {
                context.setFillColor(backing.copy(alpha: 0.65) ?? backing)
                context.fill(box)
            } else if style.text == .outline {
                context.textPosition = origin
                CTLineDraw(line(row.text, font: font, colour: backing, stroke: stroke / px * 100), context)
            }
            context.saveGState()
            if shadow > 0 {
                // flipped: positive y is down
                context.setShadow(offset: CGSize(width: 0, height: -shadow), blur: shadow * 2, color: backing.copy(alpha: 0.85))
            }
            context.textPosition = origin
            CTLineDraw(line(row.text, font: font, colour: fill), context)
            context.restoreGState()
        }
        return context.makeImage().map { ($0, bounds) }
    }

    /// Core Image coordinates.
    public static func overlay(text: String, frame: CGSize, style: SubtitleBurnStyle) -> CIImage? {
        guard let (image, rect) = bitmap(text: text, frame: frame, style: style) else { return nil }
        return CIImage(cgImage: image).transformed(by: CGAffineTransform(translationX: rect.minX, y: frame.height - rect.maxY))
    }

    #if DEBUG
    public static func selfCheck() {
        let frame = CGSize(width: 1280, height: 720)
        let style = SubtitleBurnStyle()
        guard let (image, rect) = bitmap(text: "Hello <i>there</i>", frame: frame, style: style) else { return assertionFailure("no bitmap") }
        assert(image.width == Int(rect.width) && rect.midX > 600 && rect.midX < 680 && rect.maxY > frame.height * 0.9)
        assert(bitmap(text: "  ", frame: frame, style: style) == nil)
        assert(wrap("one two three", maxWidth: 10) { CGFloat($0.count) } == ["one two", "three"])
        assert(!growsDown(y: 0) && growsDown(y: -0.6))
    }
    #endif
}

/// render queue, locked cache
final class SubtitleBurnState: @unchecked Sendable {
    private struct Key: Hashable {
        let text: String
        let style: SubtitleBurnStyle
        let width: CGFloat
        let height: CGFloat
    }

    private let lock = NSLock()
    private let cues: [SubtitleCue]
    private let style: SubtitleBurnStyle
    private var cached: (key: Key, image: CIImage?)?

    init(cues: [SubtitleCue], style: SubtitleBurnStyle) {
        self.cues = cues
        self.style = style
    }

    func overlay(atSeconds seconds: Double, frame: CGSize) -> CIImage? {
        lock.withLock {
            guard let index = SubtitleCodec.activeIndex(in: cues, atMs: seconds * 1000) else { return nil }
            let key = Key(text: cues[index].text, style: style, width: frame.width, height: frame.height)
            if let cached, cached.key == key { return cached.image }
            let image = SubtitleBurnRenderer.overlay(text: key.text, frame: frame, style: style)
            cached = (key, image)
            return image
        }
    }
}

/// Re-encodes a video with its cues drawn over each frame.
public enum SubtitleBurner {
    public enum Codec: String, CaseIterable, Sendable {
        case h264, hevc
        public var label: String { self == .h264 ? "MP4 · H.264" : "MP4 · HEVC" }
        var preset: String { self == .h264 ? AVAssetExportPresetHighestQuality : AVAssetExportPresetHEVCHighestQuality }
    }

    public struct Failure: Error {}

    @concurrent
    public static func export(video: URL, cues: [SubtitleCue], style: SubtitleBurnStyle, codec: Codec, to output: URL,
                              progress: @escaping @Sendable (Double) -> Void) async throws {
        let asset = AVURLAsset(url: video)
        guard let session = AVAssetExportSession(asset: asset, presetName: codec.preset) else { throw Failure() }
        let state = SubtitleBurnState(cues: cues, style: style)
        // frames arrive upright
        session.videoComposition = try await AVVideoComposition.videoComposition(with: asset) { request in
            let source = request.sourceImage
            let overlay = state.overlay(atSeconds: request.compositionTime.seconds, frame: request.renderSize)
            request.finish(with: overlay?.composited(over: source).cropped(to: source.extent) ?? source, context: nil)
        }
        nonisolated(unsafe) let monitored = session
        let monitor = Task {
            for await state in monitored.states(updateInterval: 0.2) {
                if case .exporting(let exporting) = state { progress(exporting.fractionCompleted) }
            }
        }
        defer { monitor.cancel() }
        try? FileManager.default.removeItem(at: output)
        try await session.export(to: output, as: .mp4)
    }
}
