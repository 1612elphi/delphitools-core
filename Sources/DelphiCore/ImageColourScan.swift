import CoreGraphics
import Foundation

/// One pass over a small copy of an image: channel histograms in the image's own encoding, where its colours fall on
/// the CIE 1931 chromaticity diagram, and how much of it lies outside sRGB or lets the background through.
public struct ImageColourScan: Sendable {
    /// Chromaticity plot range: x 0...0.8, y 0...0.9, which holds the whole spectral locus.
    public static let plot = CGSize(width: 0.8, height: 0.9)
    public static let cells = 128

    /// Red, green and blue, 256 bins each, of the pixels that are not fully transparent.
    public var histogram: [[Int]] = Array(repeating: Array(repeating: 0, count: 256), count: 3)
    /// The pixels' chromaticities, each cell in its own colour, brighter where more pixels fall; row 0 is the top.
    public var chroma: CGImage?
    /// Share of the visible, not black pixels whose colour sRGB cannot show.
    public var outsideSRGB = 0.0
    /// Share of all pixels with some transparency; nil when the image has no alpha.
    public var transparent: Double?
    /// x, y of the image space's red, green and blue primaries; nil for a space without three.
    public var primaries: [CGPoint]?

    /// sRGB's primaries, the reference triangle.
    public static let sRGB = [CGPoint(x: 0.64, y: 0.33), CGPoint(x: 0.30, y: 0.60), CGPoint(x: 0.15, y: 0.06)]
    /// D65 white.
    public static let white = CGPoint(x: 0.3127, y: 0.3290)

    /// Area of the space's triangle over sRGB's, on the xy diagram.
    public var gamutOverSRGB: Double? {
        primaries.map { Self.area($0) / Self.area(Self.sRGB) }
    }

    /// Area of a triangle of xy points.
    public static func area(_ triangle: [CGPoint]) -> Double {
        guard triangle.count == 3 else { return 0 }
        let (a, b, c) = (triangle[0], triangle[1], triangle[2])
        return abs(Double((b.x - a.x) * (c.y - a.y) - (c.x - a.x) * (b.y - a.y))) / 2
    }

    /// Scans `image`, a small copy of the file, in the file's colour `space`; `hasAlpha` is the file's alpha flag.
    public static func scan(_ image: CGImage, space: CGColorSpace?, hasAlpha: Bool) -> ImageColourScan {
        var scan = ImageColourScan()
        let rgb = space.flatMap { $0.model == .rgb ? $0 : nil }
        scan.primaries = rgb.flatMap(primaries)
        scan.countChannels(image, space: rgb ?? CGColorSpace(name: CGColorSpace.sRGB)!, hasAlpha: hasAlpha)
        scan.plotChromaticity(image)
        return scan
    }

    // image's own encoding
    private mutating func countChannels(_ image: CGImage, space: CGColorSpace, hasAlpha: Bool) {
        let (width, height) = (image.width, image.height)
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) ?? CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
        guard let context, let data = context.data else { return }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let pixels = data.bindMemory(to: UInt8.self, capacity: width * height * 4)
        var bins = histogram
        var seeThrough = 0
        for index in 0..<width * height {
            let pixel = pixels + index * 4
            let alpha = Int(pixel[3])
            if alpha < 255 { seeThrough += 1 }
            guard alpha > 0 else { continue }
            for channel in 0..<3 { bins[channel][min(255, Int(pixel[channel]) * 255 / alpha)] += 1 }
        }
        histogram = bins
        transparent = hasAlpha ? Double(seeThrough) / Double(max(1, width * height)) : nil
    }

    // negatives keep out-of-gamut chromaticity
    private mutating func plotChromaticity(_ image: CGImage) {
        let (width, height) = (image.width, image.height)
        guard let linear = CGColorSpace(name: CGColorSpace.extendedLinearSRGB),
              let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 32, bytesPerRow: width * 16, space: linear,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.floatComponents.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
              ),
              let data = context.data else { return }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let pixels = data.bindMemory(to: Float.self, capacity: width * height * 4)
        let cells = Self.cells
        var counts = [UInt32](repeating: 0, count: cells * cells)
        var coloured = 0
        var outside = 0
        for index in 0..<width * height {
            let pixel = pixels + index * 4
            let alpha = Double(pixel[3])
            guard alpha > 0.004 else { continue }
            let red = Double(pixel[0]) / alpha, green = Double(pixel[1]) / alpha, blue = Double(pixel[2]) / alpha
            let brightest = max(red, green, blue)
            // black has no chromaticity
            guard brightest > 0.002 else { continue }
            coloured += 1
            if min(red, green, blue) < -0.01 * brightest { outside += 1 }
            guard let point = Self.chromaticity(red: red, green: green, blue: blue) else { continue }
            let across = Int(point.x / Self.plot.width * CGFloat(cells))
            let down = Int((1 - point.y / Self.plot.height) * CGFloat(cells))
            guard (0..<cells).contains(across), (0..<cells).contains(down) else { continue }
            counts[down * cells + across] += 1
        }
        outsideSRGB = Double(outside) / Double(max(1, coloured))
        chroma = Self.densityImage(counts)
    }

    /// CIE xy of a linear sRGB colour; nil for black.
    public static func chromaticity(red: Double, green: Double, blue: Double) -> CGPoint? {
        let x = 0.4124 * red + 0.3576 * green + 0.1805 * blue
        let y = 0.2126 * red + 0.7152 * green + 0.0722 * blue
        let z = 0.0193 * red + 0.1192 * green + 0.9505 * blue
        let sum = x + y + z
        guard sum > 1e-6 else { return nil }
        return CGPoint(x: x / sum, y: y / sum)
    }

    /// xy of `space`'s red, green and blue primaries; nil for a space that is not three-channel RGB.
    public static func primaries(of space: CGColorSpace) -> [CGPoint]? {
        guard space.model == .rgb, space.numberOfComponents == 3, let linear = CGColorSpace(name: CGColorSpace.extendedLinearSRGB) else { return nil }
        let points = [[1.0, 0, 0, 1], [0, 1.0, 0, 1], [0, 0, 1.0, 1]].compactMap { components -> CGPoint? in
            guard let colour = CGColor(colorSpace: space, components: components.map { CGFloat($0) }),
                  let converted = colour.converted(to: linear, intent: .relativeColorimetric, options: nil)?.components,
                  converted.count >= 3 else { return nil }
            return chromaticity(red: Double(converted[0]), green: Double(converted[1]), blue: Double(converted[2]))
        }
        return points.count == 3 ? points : nil
    }

    // log alpha: singles visible
    private static func densityImage(_ counts: [UInt32]) -> CGImage? {
        let cells = Self.cells
        guard let most = counts.max(), most > 0 else { return nil }
        let scale = log1p(Double(most))
        var bytes = [UInt8](repeating: 0, count: cells * cells * 4)
        for down in 0..<cells {
            for across in 0..<cells {
                let cell = down * cells + across
                guard counts[cell] > 0 else { continue }
                let alpha = 0.3 + 0.7 * log1p(Double(counts[cell])) / scale
                let x = (Double(across) + 0.5) / Double(cells) * Double(plot.width)
                let y = (1 - (Double(down) + 0.5) / Double(cells)) * Double(plot.height)
                let ink = display(x: x, y: y)
                for part in 0..<3 { bytes[cell * 4 + part] = UInt8(ink[part] * alpha * 255) }
                bytes[cell * 4 + 3] = UInt8(alpha * 255)
            }
        }
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(
            width: cells, height: cells, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: cells * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        )
    }

    /// Gamma-encoded sRGB, 0...1, of chromaticity x, y at full brightness, for drawing the diagram.
    public static func display(x: Double, y: Double) -> [Double] {
        guard y > 1e-4 else { return [0, 0, 0] }
        let big = (x: x / y, y: 1.0, z: (1 - x - y) / y)
        let linear = [
            3.2406 * big.x - 1.5372 * big.y - 0.4986 * big.z,
            -0.9689 * big.x + 1.8758 * big.y + 0.0415 * big.z,
            0.0557 * big.x - 0.2040 * big.y + 1.0570 * big.z,
        ].map { max(0, $0) }
        let top = max(linear.max() ?? 1, 1e-6)
        return linear.map { value in
            let share = value / top
            return share <= 0.0031308 ? share * 12.92 : 1.055 * pow(share, 1 / 2.4) - 0.055
        }
    }

    /// CIE 1931 2° spectral locus, 380 to 700 nm in 5 nm steps, from the CVRL colour matching functions.
    public static let locus: [CGPoint] = [
        (0.1741, 0.0050), (0.1740, 0.0050), (0.1738, 0.0049), (0.1736, 0.0049), (0.1733, 0.0048), (0.1730, 0.0048),
        (0.1726, 0.0048), (0.1721, 0.0048), (0.1714, 0.0051), (0.1703, 0.0058), (0.1689, 0.0069), (0.1669, 0.0086),
        (0.1644, 0.0109), (0.1611, 0.0138), (0.1566, 0.0177), (0.1510, 0.0227), (0.1440, 0.0297), (0.1355, 0.0399),
        (0.1241, 0.0578), (0.1096, 0.0868), (0.0913, 0.1327), (0.0687, 0.2007), (0.0454, 0.2950), (0.0235, 0.4127),
        (0.0082, 0.5384), (0.0039, 0.6548), (0.0139, 0.7502), (0.0389, 0.8120), (0.0743, 0.8338), (0.1142, 0.8262),
        (0.1547, 0.8059), (0.1929, 0.7816), (0.2296, 0.7543), (0.2658, 0.7243), (0.3016, 0.6923), (0.3374, 0.6588),
        (0.3731, 0.6245), (0.4087, 0.5896), (0.4441, 0.5547), (0.4788, 0.5202), (0.5125, 0.4866), (0.5448, 0.4544),
        (0.5752, 0.4242), (0.6029, 0.3965), (0.6270, 0.3725), (0.6482, 0.3514), (0.6658, 0.3340), (0.6801, 0.3197),
        (0.6915, 0.3083), (0.7006, 0.2993), (0.7079, 0.2920), (0.7140, 0.2859), (0.7190, 0.2809), (0.7230, 0.2769),
        (0.7260, 0.2740), (0.7283, 0.2717), (0.7300, 0.2700), (0.7311, 0.2689), (0.7320, 0.2680), (0.7327, 0.2673),
        (0.7334, 0.2666), (0.7340, 0.2660), (0.7344, 0.2656), (0.7346, 0.2654), (0.7347, 0.2653),
    ].map { CGPoint(x: $0.0, y: $0.1) }

    /// Nanometres of `locus[index]`.
    public static func wavelength(at index: Int) -> Int { 380 + index * 5 }
}
