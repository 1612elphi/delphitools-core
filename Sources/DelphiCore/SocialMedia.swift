import CoreGraphics
import CoreImage
import Foundation
import ImageIO

// MARK: - Cropper

public struct CropRatio: Equatable, Sendable {
    public let id: String
    public let name: String
    public let widthRatio: CGFloat
    public let heightRatio: CGFloat

    public init(id: String, name: String, widthRatio: CGFloat, heightRatio: CGFloat) {
        (self.id, self.name, self.widthRatio, self.heightRatio) = (id, name, widthRatio, heightRatio)
    }

    public var aspectRatio: CGFloat { widthRatio / heightRatio }

    /// e.g. 1.91:1
    public var label: String { String(format: "%g:%g", widthRatio, heightRatio) }
}

public struct CropPlatform: Equatable, Sendable {
    public let id: String
    public let name: String
    public let ratios: [CropRatio]

    public init(id: String, name: String, ratios: [CropRatio]) {
        (self.id, self.name, self.ratios) = (id, name, ratios)
    }
}

public enum CropPresets {
    private static let square = String(localized: "Square")
    private static let portrait = String(localized: "Portrait")
    private static let landscape = String(localized: "Landscape")

    private static func platform(_ id: String, _ name: String, _ ratios: [(key: String, name: String, width: CGFloat, height: CGFloat)]) -> CropPlatform {
        CropPlatform(id: id, name: name, ratios: ratios.map {
            CropRatio(id: "\(id)-\($0.key)", name: $0.name, widthRatio: $0.width, heightRatio: $0.height)
        })
    }

    /// x omitted deliberately
    public static let all: [CropPlatform] = [
        // from the web presets
        platform("bluesky", "Bluesky", [
            ("square", square, 1, 1), ("landscape", landscape, 16, 9), ("portrait", portrait, 3, 4), ("wide", String(localized: "Wide"), 2, 1),
        ]),
        // facebook.com/business/ads-guide/update/image (2026-09-26)
        platform("facebook", "Facebook", [
            ("portrait", portrait, 4, 5), ("square", square, 1, 1), ("landscape", landscape, 1.91, 1), ("stories", String(localized: "Stories"), 9, 16),
        ]),
        // 3:4 since 2025: influencermarketinghub.com/instagram-image-sizes
        platform("instagram", "Instagram", [
            ("square", square, 1, 1), ("portrait", portrait, 3, 4), ("classic", String(localized: "Classic"), 4, 5),
            ("landscape", landscape, 1.91, 1), ("reels", "Reels", 9, 16),
        ]),
        // linkedin.com/help/lms/answer/a426534 (2026-09-26)
        platform("linkedin", "LinkedIn", [
            ("square", square, 1, 1), ("portrait", portrait, 4, 5), ("landscape", landscape, 1.91, 1),
        ]),
        // docs.joinmastodon.org/user/posting (2026-09-26)
        platform("mastodon", "Mastodon", [("preview", String(localized: "Preview"), 16, 9)]),
        // help.pinterest.com/en/business/article/pinterest-product-specs (2026-09-26)
        platform("pinterest", "Pinterest", [("portrait", portrait, 2, 3), ("square", square, 1, 1)]),
        // from the web presets
        platform("threads", "Threads", [
            ("square", square, 1, 1), ("portrait", portrait, 4, 5), ("landscape", landscape, 1.91, 1), ("stories", String(localized: "Stories"), 9, 16),
        ]),
        // ads.tiktok.com/help/article/tiktok-auction-in-feed-ads (2026-09-26)
        platform("tiktok", "TikTok", [("portrait", portrait, 9, 16), ("square", square, 1, 1), ("landscape", landscape, 16, 9)]),
        // support.google.com/youtube/answer/72431, /7124474
        platform("youtube", "YouTube", [
            ("thumbnail", String(localized: "Thumbnail"), 16, 9), ("shorts", "Shorts", 9, 16), ("post", String(localized: "Post"), 1, 1),
        ]),
    ]

    public static let instagram = all.first { $0.id == "instagram" }!
}

/// The crop of a social cropper: a platform's ratio placed over the image by its centre.
public struct SocialCrop: Sendable {
    public private(set) var platform = CropPresets.instagram
    public private(set) var ratio = CropPresets.instagram.ratios[0]
    public private(set) var imageSize = CGSize.zero
    /// image pixels, clamped
    private var centre = CGPoint.zero

    public init() {}

    /// image pixels, top-left origin
    public var rect: CGRect { Self.crop(aspect: ratio.aspectRatio, in: imageSize, centre: centre) }

    /// largest crop, clamped centre
    public static func crop(aspect: CGFloat, in size: CGSize, centre: CGPoint) -> CGRect {
        guard size.width > 0, size.height > 0, aspect > 0 else { return .zero }
        // cropping rounds fractions outward
        let width = min(size.width, size.height * aspect).rounded()
        let height = min(size.height, width / aspect).rounded()
        return CGRect(
            x: min(max((centre.x - width / 2).rounded(), 0), size.width - width),
            y: min(max((centre.y - height / 2).rounded(), 0), size.height - height),
            width: width, height: height
        )
    }

    private mutating func clampCentre() {
        let crop = rect
        centre = CGPoint(x: crop.midX, y: crop.midY)
    }

    public mutating func setImage(_ size: CGSize) {
        imageSize = size
        centre = CGPoint(x: size.width / 2, y: size.height / 2)
    }

    /// keeps same-named ratio
    public mutating func select(_ platform: CropPlatform) {
        self.platform = platform
        ratio = platform.ratios.first { $0.name == ratio.name } ?? platform.ratios[0]
        clampCentre()
    }

    public mutating func select(_ ratio: CropRatio) {
        self.ratio = ratio
        clampCentre()
    }

    /// `delta` in points of a picture `shown` wide
    public mutating func drag(_ delta: CGPoint, shownWidth: CGFloat) {
        guard shownWidth > 0 else { return }
        let scale = imageSize.width / shownWidth
        centre = CGPoint(x: centre.x + delta.x * scale, y: centre.y + delta.y * scale)
        clampCentre()
    }

    #if DEBUG
    public static func selfCheck() {
        let ratios = CropPresets.all.flatMap(\.ratios)
        assert(ratios.allSatisfy { $0.widthRatio > 0 && $0.heightRatio > 0 }, "every ratio positive")
        assert(Set(ratios.map(\.id)).count == ratios.count && Set(CropPresets.all.map(\.id)).count == CropPresets.all.count, "unique ids")
        assert(CropPresets.all.allSatisfy { !$0.ratios.isEmpty && Set($0.ratios.map(\.label)).count == $0.ratios.count }, "one label per ratio")
        assert(!CropPresets.all.contains { ["x", "twitter"].contains($0.id) })
        assert(CropPresets.instagram.ratios.map(\.label) == ["1:1", "3:4", "4:5", "1.91:1", "9:16"])
        let size = CGSize(width: 3000, height: 2000)
        assert(crop(aspect: 1, in: size, centre: CGPoint(x: 1500, y: 1000)) == CGRect(x: 500, y: 0, width: 2000, height: 2000))
        assert(crop(aspect: 1, in: size, centre: CGPoint(x: 2900, y: 0)) == CGRect(x: 1000, y: 0, width: 2000, height: 2000), "clamped")
        assert(crop(aspect: 2, in: size, centre: CGPoint(x: 1500, y: 1000)) == CGRect(x: 0, y: 250, width: 3000, height: 1500))

        var model = SocialCrop()
        model.setImage(size)
        assert(model.rect == CGRect(x: 500, y: 0, width: 2000, height: 2000), "starts centred")
        model.drag(CGPoint(x: 30, y: 0), shownWidth: 300)
        assert(model.rect.minX == 800, "drag in view points")
        model.select(CropPresets.instagram.ratios[1])
        assert(model.rect == CGRect(x: 1050, y: 0, width: 1500, height: 2000), "keeps the centre")
        model.select(CropPresets.all.first { $0.id == "bluesky" }!)
        assert(model.ratio.id == "bluesky-portrait" && model.rect.midX == 1800, "same name, same centre")
        model.drag(CGPoint(x: 100, y: 0), shownWidth: 300)
        assert(model.rect.maxX == 3000, "clamped at the edge")
    }
    #endif
}

// MARK: - Matte

/// mirrors web matte
public nonisolated struct MatteSpec: Equatable, Sendable {
    public enum Style: Int, Sendable { case blurred, solid, gradient }

    public struct RGB: Equatable, Sendable {
        public var r: Int
        public var g: Int
        public var b: Int

        public init(r: Int, g: Int, b: Int) {
            (self.r, self.g, self.b) = (r, g, b)
        }

        /// clamped to sRGB bytes; p3 picks exceed 0...1
        public init(_ colour: CGColor) {
            let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
            let parts = colour.converted(to: srgb, intent: .relativeColorimetric, options: nil)?.components ?? [0, 0, 0, 1]
            let byte = { (value: CGFloat) in Int((min(max(value, 0), 1) * 255).rounded()) }
            let grey = parts.count < 3
            self.init(r: byte(parts[0]), g: byte(parts[grey ? 0 : 1]), b: byte(parts[grey ? 0 : 2]))
        }

        public var cgColor: CGColor { CGColor(srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: 1) }

        /// clamped to 0...255
        public func shifted(_ amount: Int) -> RGB {
            let clamp = { (value: Int) in min(255, max(0, value + amount)) }
            return RGB(r: clamp(r), g: clamp(g), b: clamp(b))
        }
    }

    /// output px, web blur(50px)
    public static let blur: CGFloat = 50
    /// hides blur edges
    public static let overscan: CGFloat = 1.2
    /// second stop channel offset
    public static let falloff = -30
    // ponytail: long side capped at 8192 (about 150 MB of pixels at 9:16); the web has no cap
    public static let longestSide = 8192

    public var style = Style.blurred
    public var colour = RGB(r: 255, g: 255, b: 255)
    public var dominant = RGB(r: 136, g: 136, b: 136)
    public var ratioW = 1
    public var ratioH = 1
    public var width = 1080
    public var padding = 40

    public init() {}

    public var height: Int { Int((Double(width * ratioH) / Double(ratioW)).rounded()) }
    public var size: CGSize { CGSize(width: width, height: height) }
    public var widthLimit: Int { ratioW >= ratioH ? Self.longestSide : Self.longestSide * ratioW / ratioH }

    public static func fit(_ image: CGSize, in box: CGSize, padding: CGFloat) -> CGRect {
        guard image.width > 0, image.height > 0 else { return .zero }
        let scale = max(0, min((box.width - padding * 2) / image.width, (box.height - padding * 2) / image.height))
        return centred(CGSize(width: image.width * scale, height: image.height * scale), in: box)
    }

    public static func cover(_ image: CGSize, in box: CGSize, overscan: CGFloat) -> CGRect {
        guard image.width > 0, image.height > 0 else { return .zero }
        let scale = max(box.width / image.width, box.height / image.height) * overscan
        return centred(CGSize(width: image.width * scale, height: image.height * scale), in: box)
    }

    private static func centred(_ size: CGSize, in box: CGSize) -> CGRect {
        CGRect(x: (box.width - size.width) / 2, y: (box.height - size.height) / 2, width: size.width, height: size.height)
    }

    private static let context = CIContext()

    /// The image covering `box`, overscanned and blurred by `blur` pixels.
    public static func backdrop(_ image: CGImage, box: CGSize, blur: CGFloat) -> CGImage? {
        let pixels = CGSize(width: image.width, height: image.height)
        let cover = cover(pixels, in: box, overscan: overscan)
        let frame = CGRect(origin: .zero, size: box)
        let placed = CIImage(cgImage: image)
            .transformed(by: CGAffineTransform(scaleX: cover.width / pixels.width, y: cover.height / pixels.height))
            // origin bottom left
            .transformed(by: CGAffineTransform(translationX: cover.minX, y: box.height - cover.maxY))
        return context.createCGImage(placed.clampedToExtent().applyingGaussianBlur(sigma: blur).cropped(to: frame), from: frame)
    }

    public static func average(_ image: CGImage) -> RGB? {
        let input = CIImage(cgImage: image)
        let mean = input.applyingFilter("CIAreaAverage", parameters: [kCIInputExtentKey: CIVector(cgRect: input.extent)])
        var pixel = [UInt8](repeating: 0, count: 4)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        context.render(mean, toBitmap: &pixel, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBA8, colorSpace: space)
        return RGB(r: Int(pixel[0]), g: Int(pixel[1]), b: Int(pixel[2]))
    }

    /// The matte at full size, sRGB, opaque.
    public func render(_ image: CGImage) -> CGImage? {
        let box = size
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let canvas = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                     bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { return nil }
        let frame = CGRect(origin: .zero, size: box)
        switch style {
        case .solid:
            canvas.setFillColor(colour.cgColor)
            canvas.fill(frame)
        case .gradient:
            let stops = [dominant.cgColor, dominant.shifted(Self.falloff).cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: space, colors: stops, locations: [0, 1]) {
                // top left to bottom right
                canvas.drawLinearGradient(gradient, start: CGPoint(x: 0, y: box.height), end: CGPoint(x: box.width, y: 0), options: [])
            }
        case .blurred:
            if let backdrop = Self.backdrop(image, box: box, blur: Self.blur) { canvas.draw(backdrop, in: frame) }
        }
        canvas.interpolationQuality = .high
        let fit = Self.fit(CGSize(width: image.width, height: image.height), in: box, padding: CGFloat(padding))
        canvas.draw(image, in: CGRect(x: fit.minX, y: box.height - fit.maxY, width: fit.width, height: fit.height))
        return canvas.makeImage()
    }

    #if DEBUG
    public static func selfCheck() {
        var spec = MatteSpec()
        spec.ratioW = 4
        spec.ratioH = 5
        assert(spec.size == CGSize(width: 1080, height: 1350))
        spec.ratioW = 9
        spec.ratioH = 16
        assert(spec.height == 1920 && spec.widthLimit == 4608)
        spec.ratioW = 16
        spec.ratioH = 9
        assert(spec.height == 608 && spec.widthLimit == 8192)

        let box = CGSize(width: 100, height: 100)
        assert(fit(CGSize(width: 200, height: 100), in: box, padding: 10) == CGRect(x: 10, y: 30, width: 80, height: 40))
        assert(fit(CGSize(width: 200, height: 100), in: box, padding: 60).width == 0)
        assert(cover(CGSize(width: 200, height: 100), in: box, overscan: 1) == CGRect(x: -50, y: 0, width: 200, height: 100))
        assert(RGB(r: 20, g: 136, b: 250).shifted(-30) == RGB(r: 0, g: 106, b: 220))
        assert(RGB(PlaceholderSpec.colour("#1e6626")) == RGB(r: 30, g: 102, b: 38))

        // red photo, padding 10
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let red = CGContext(data: nil, width: 2, height: 1, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        red.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
        red.fill(CGRect(x: 0, y: 0, width: 2, height: 1))
        var solid = MatteSpec()
        solid.style = .solid
        solid.width = 100
        solid.padding = 10
        guard let out = solid.render(red.makeImage()!), let data = out.dataProvider?.data, let bytes = CFDataGetBytePtr(data) else {
            return assertionFailure("render")
        }
        assert(out.width == 100 && out.height == 100)
        let pixel = { (x: Int, y: Int) in (0..<3).map { Int(bytes[y * out.bytesPerRow + x * 4 + $0]) } }
        assert(pixel(2, 2).allSatisfy { $0 > 250 }, "matte corner")
        assert(pixel(50, 50) == [255, 0, 0], "photo centre")
        assert(pixel(50, 20).allSatisfy { $0 > 250 }, "padding band above the photo")

        var gradient = MatteSpec()
        gradient.style = .gradient
        gradient.width = 100
        gradient.padding = 60
        gradient.dominant = RGB(r: 200, g: 200, b: 200)
        guard let ramp = gradient.render(red.makeImage()!), let rampData = ramp.dataProvider?.data, let rampBytes = CFDataGetBytePtr(rampData) else {
            return assertionFailure("gradient")
        }
        assert(rampBytes[0] > rampBytes[99 * ramp.bytesPerRow + 99 * 4], "lighter at the top left")
    }
    #endif
}

// MARK: - Scroll

/// never crops, unlike web
public nonisolated enum ScrollEngine {
    /// width/height, shape row order
    public static let ratios = [4.0 / 5.0, 1.0]
    /// output px, web value
    public static let blur = 30.0
    /// 8192² pixels, any shape
    public static let maxArea = 8192 * 8192

    public enum Fill: Equatable, Sendable {
        case blur
        case colour(red: CGFloat, green: CGFloat, blue: CGFloat)
    }

    public struct Geometry: Equatable, Sendable {
        public let tileWidth: Int
        public let tileHeight: Int
        public let slideCount: Int
        public let needsFill: Bool
        public let imageWidth: Int
        /// strip pixels
        public let imageStart: Double
    }

    /// image pixels
    public struct Slice: Equatable, Sendable {
        public let sourceX: Double
        public let sourceWidth: Double
        public let drawX: Double
        public let isFillEdge: Bool
    }

    public static func geometry(width: Int, height: Int, ratio: Double) -> Geometry? {
        guard width > 0, height > 0 else { return nil }
        let tileWidth = max(1, Int((Double(height) * ratio).rounded()))
        let slideCount = max(1, (width + tileWidth - 1) / tileWidth)
        let fill = tileWidth * slideCount - width
        // no half-pixel seam
        return Geometry(
            tileWidth: tileWidth, tileHeight: height, slideCount: slideCount, needsFill: fill > 0, imageWidth: width,
            imageStart: Double(fill / 2)
        )
    }

    /// The longest side to decode `url` at so its area stays within `maxArea`.
    public static func longestSide(_ url: URL) -> Int {
        guard let file = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(file, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int, width > 0, height > 0
        else { return 8192 }
        let scale = min(1, (Double(maxArea) / Double(width * height)).squareRoot())
        return Int(Double(max(width, height)) * scale)
    }

    /// handles capped decodes
    public static func slideSize(_ geometry: Geometry, imageHeight: Int) -> CGSize {
        let scale = Double(imageHeight) / Double(geometry.tileHeight)
        return CGSize(width: max(1, (Double(geometry.tileWidth) * scale).rounded()), height: Double(imageHeight))
    }

    public static func slices(_ geometry: Geometry) -> [Slice] {
        let imageEnd = geometry.imageStart + Double(geometry.imageWidth)
        return (0..<geometry.slideCount).map { index in
            let tileStart = Double(index * geometry.tileWidth)
            let start = max(tileStart, geometry.imageStart)
            let end = min(tileStart + Double(geometry.tileWidth), imageEnd)
            let hasContent = end > start
            return Slice(
                sourceX: hasContent ? start - geometry.imageStart : 0, sourceWidth: hasContent ? end - start : 0,
                drawX: hasContent ? start - tileStart : 0,
                isFillEdge: geometry.needsFill && (index == 0 || index == geometry.slideCount - 1)
            )
        }
    }

    /// accepts smaller copies
    public struct Renderer: Sendable {
        private let image: CGImage
        private let fill: Fill
        private let scale: Double
        private let size: CGSize
        private let slices: [Slice]

        public init(_ image: CGImage, geometry: Geometry, fill: Fill) {
            self.image = image
            self.fill = fill
            scale = Double(image.height) / Double(geometry.tileHeight)
            size = ScrollEngine.slideSize(geometry, imageHeight: image.height)
            slices = ScrollEngine.slices(geometry)
        }

        public func slides() -> [CGImage] {
            slices.indices.compactMap { Task.isCancelled ? nil : slide($0) }
        }

        public func slide(_ index: Int) -> CGImage? {
            let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
            let space = image.colorSpace.flatMap { $0.model == .rgb && $0.supportsOutput ? $0 : nil } ?? srgb
            guard slices.indices.contains(index),
                  let canvas = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0,
                                         space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
                  ?? CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0,
                               space: srgb, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return nil }
            let slice = slices[index]
            let tile = CGRect(origin: .zero, size: size)
            let crop = slice.sourceWidth > 0
                ? image.cropping(to: CGRect(x: slice.sourceX * scale, y: 0, width: slice.sourceWidth * scale, height: size.height))
                : nil
            if slice.isFillEdge {
                switch fill {
                case .colour(let red, let green, let blue):
                    canvas.setFillColor(CGColor(srgbRed: red, green: green, blue: blue, alpha: 1))
                    canvas.fill(tile)
                case .blur:
                    if let crop, let blurred = MatteSpec.backdrop(crop, box: tile.size, blur: ScrollEngine.blur * scale) {
                        canvas.draw(blurred, in: tile)
                    }
                }
            }
            if let crop {
                canvas.draw(crop, in: CGRect(x: slice.drawX * scale, y: 0, width: slice.sourceWidth * scale, height: size.height))
            }
            return canvas.makeImage()
        }
    }

    #if DEBUG
    public static func selfCheck() {
        let fills = geometry(width: 3000, height: 1350, ratio: 0.8)!
        assert(fills.tileWidth == 1080 && fills.slideCount == 3 && fills.needsFill && fills.imageStart == 120)
        assert(slices(fills) == [
            Slice(sourceX: 0, sourceWidth: 960, drawX: 120, isFillEdge: true),
            Slice(sourceX: 960, sourceWidth: 1080, drawX: 0, isFillEdge: false),
            Slice(sourceX: 2040, sourceWidth: 960, drawX: 0, isFillEdge: true),
        ])
        assert(geometry(width: 3240, height: 1350, ratio: 0.8)!.needsFill == false)
        // rounds up: never crops
        let over = geometry(width: 3600, height: 1350, ratio: 0.8)!
        assert(over.slideCount == 4 && over.needsFill && over.imageStart == 360 && slices(over)[0] == Slice(sourceX: 0, sourceWidth: 720, drawX: 360, isFillEdge: true))
        let square = geometry(width: 3000, height: 2000, ratio: 1)!
        assert(square.slideCount == 2 && square.imageStart == 500 && slices(square)[1] == Slice(sourceX: 1500, sourceWidth: 1500, drawX: 0, isFillEdge: true))
        let narrow = geometry(width: 300, height: 2000, ratio: 0.8)!
        assert(narrow.slideCount == 1 && narrow.imageStart == 650 && slices(narrow) == [Slice(sourceX: 0, sourceWidth: 300, drawX: 650, isFillEdge: true)])
        assert(geometry(width: 3241, height: 1350, ratio: 0.8)!.slideCount == 4, "one pixel over is a slide more")
        let tall = geometry(width: 500, height: 2000, ratio: 1)!
        assert(tall.slideCount == 1 && tall.needsFill && slices(tall)[0].drawX == 750)
        assert(geometry(width: 0, height: 10, ratio: 1) == nil)

        // fill, image, fill
        let blue = CGContext(data: nil, width: 300, height: 135, bitsPerComponent: 8, bytesPerRow: 0,
                             space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        blue.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 1, alpha: 1))
        blue.fill(CGRect(x: 0, y: 0, width: 300, height: 135))
        let small = geometry(width: 300, height: 135, ratio: 0.8)!
        let first = Renderer(blue.makeImage()!, geometry: small, fill: .colour(red: 1, green: 0, blue: 0)).slide(0)!
        assert(first.width == 108 && first.height == 135)
        let pixels = CFDataGetBytePtr(first.dataProvider!.data)!
        let pixel = { (x: Int) in (pixels[60 * first.bytesPerRow + x * 4], pixels[60 * first.bytesPerRow + x * 4 + 2]) }
        assert(pixel(2) == (255, 0) && pixel(60) == (0, 255))
        let sliver = blue.makeImage()!.cropping(to: CGRect(x: 0, y: 0, width: 30, height: 135))!
        let alone = Renderer(sliver, geometry: geometry(width: 30, height: 135, ratio: 0.8)!, fill: .colour(red: 1, green: 0, blue: 0)).slide(0)!
        let lone = CFDataGetBytePtr(alone.dataProvider!.data)!
        let fillsBothSides = [2, 50, 100].map { lone[60 * alone.bytesPerRow + $0 * 4] }
        assert(alone.width == 108 && fillsBothSides == [255, 0, 255], "a sliver sits in one slide, fill either side")
    }
    #endif
}
