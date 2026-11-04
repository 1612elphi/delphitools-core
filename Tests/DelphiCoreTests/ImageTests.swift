import CoreImage
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import DelphiCore

@Test func imageAtlasReport() {
    #expect(ImageAtlasReport.prettyLabel("DateTimeOriginal") == "Date Taken")
    #expect(ImageAtlasReport.prettyLabel("LensModel") == "Lens Model")
    #expect(ImageAtlasReport.prettyLabel("FNumber") == "F-Number" && ImageAtlasReport.prettyLabel("sRGBIntent") == "sRGB Intent")
    #expect(ImageAtlasReport.prettyValue(key: "fnumber", raw: 2.8) == "f/2.8")
    #expect(ImageAtlasReport.prettyValue(key: "exposuretime", raw: 0.005) == "0.005 (1/200s)")
    #expect(ImageAtlasReport.prettyValue(key: "focallength", raw: 50.0) == "50 mm")
    #expect(ImageAtlasReport.prettyValue(key: "meteringmode", raw: 3) == "Spot")
    #expect(ImageAtlasReport.prettyValue(key: "altitude", raw: 12.4) == "12.4 m" && ImageAtlasReport.prettyValue(key: "imgdirection", raw: 58.2) == "58.2°")
    #expect(ImageAtlasReport.prettyValue(key: "subjectdistance", raw: ImageAtlasReport.infinityThreshold) == "Infinity")
    #expect(ImageAtlasReport.prettyValue(key: "focallength", raw: Double.infinity) == "inf mm")
    #expect(ImageAtlasReport.prettyValue(key: "exposuretime", raw: Double.nan) == "nan")
    #expect(ImageAtlasReport.prettyValue(key: "exposuretime", raw: 1e-300) == "0")
    #expect(ImageAtlasReport.prettyValue(key: "brightnessvalue", raw: 1e300) == "1e+300")
    #expect(ImageAtlasReport.prettyValue(key: "other", raw: [1.5, Double.infinity] as [Any]) == "1.5, inf")
    #expect(ImageAtlasReport.prettyValue(key: "other", raw: ["a": 1] as [String: Any]).contains("a"))
    #expect(!ImageAtlasReport.build(data: Data("not an image".utf8), filename: "x").readable)
}


@Test func imageColourScan() {
    func near(_ a: CGPoint?, _ b: CGPoint, _ within: CGFloat = 0.006) -> Bool {
        guard let a else { return false }
        return abs(a.x - b.x) < within && abs(a.y - b.y) < within
    }
    #expect(near(ImageColourScan.chromaticity(red: 1, green: 1, blue: 1), ImageColourScan.white, 0.001))
    let srgb = ImageColourScan.primaries(of: CGColorSpace(name: CGColorSpace.sRGB)!)
    #expect(srgb.map { zip($0, ImageColourScan.sRGB).allSatisfy { near($0, $1) } } == true, "ImageColourScan.sRGB primaries")
    let p3 = ImageColourScan.primaries(of: CGColorSpace(name: CGColorSpace.displayP3)!)
    #expect(near(p3?.first, CGPoint(x: 0.680, y: 0.320)) && near(p3?[1], CGPoint(x: 0.265, y: 0.690)), "P3 primaries")
    #expect(abs(ImageColourScan.area(ImageColourScan.sRGB) - 0.1121) < 0.001)
    let wide = ImageColourScan(primaries: p3).gamutOverSRGB ?? 0
    #expect(wide > 1.3 && wide < 1.4, "P3 is about 1.36 ImageColourScan.sRGB")
    #expect(ImageColourScan.display(x: 0.64, y: 0.33).map { ($0 * 100).rounded() } == [100, 0, 0])

    let space = CGColorSpace(name: CGColorSpace.displayP3)!
    let context = CGContext(data: nil, width: 4, height: 2, bitsPerComponent: 8, bytesPerRow: 16, space: space,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(CGColor(colorSpace: space, components: [1, 0, 0, 1])!)
    context.fill(CGRect(x: 0, y: 1, width: 4, height: 1))
    let scan = ImageColourScan.scan(context.makeImage()!, space: space, hasAlpha: true)
    #expect(scan.transparent == 0.5 && abs(scan.outsideSRGB - 1) < 1e-9, "red outside, half clear")
    #expect(scan.histogram[0][255] == 4 && scan.histogram[1][0] == 4 && scan.histogram[0].reduce(0, +) == 4)
    #expect(scan.chroma != nil)
}


@Test func maskShapes() {
    #expect(MaskShapes.all.count == 28 * MaskShapes.variants)
    #expect(Set(MaskShapes.all.map(\.id)).count == MaskShapes.all.count)
    #expect(MaskShapes.default.id == "squircle-4")
    #expect(MaskShapes.all.allSatisfy { !$0.path.isEmpty })
    // web mulberry32(1) reference
    let rnd = MaskRandom(seed: 1)
    #expect(abs(rnd.next() - 0.6270739405881613) < 1e-12)
}


@Test func imageDeskew() {
    let quad = ImageDeskewEngine.insetQuad(width: 100, height: 200)
    #expect(quad[0] == CGPoint(x: 12, y: 24))
    #expect(quad[2] == CGPoint(x: 88, y: 176))
    #expect(ImageDeskewEngine.outputSize(quad: quad) == CGSize(width: 76, height: 152))
    #expect(ImageDeskewEngine.fitAspect(CGSize(width: 100, height: 50), ratio: nil) == CGSize(width: 100, height: 50))
    #expect(ImageDeskewEngine.fitAspect(CGSize(width: 100, height: 50), ratio: 1) == CGSize(width: 100, height: 100))
    #expect(ImageDeskewEngine.fitAspect(CGSize(width: 50, height: 100), ratio: 1) == CGSize(width: 100, height: 100))
    #expect(ImageDeskewEngine.capped(CGSize(width: 16384, height: 4096)) == CGSize(width: 8192, height: 2048))
    #expect(ImageDeskewEngine.capped(CGSize(width: 100, height: 50)) == CGSize(width: 100, height: 50))

    #expect(ImageDeskewEngine.isConvex(quad))
    #expect(!ImageDeskewEngine.isConvex([quad[1], quad[0], quad[2], quad[3]]), "bow-tie")
    #expect(!ImageDeskewEngine.isConvex(Array(quad.reversed())), "mirrored")
    #expect(!ImageDeskewEngine.isConvex([quad[0], quad[0], quad[2], quad[3]]), "collapsed")
    #expect(!ImageDeskewEngine.isConvex([quad[0], quad[1], CGPoint(x: 20, y: 30), quad[3]]), "concave")

    // quadrant colours per corner
    let red = CIImage(color: .red).cropped(to: CGRect(x: 0, y: 50, width: 100, height: 50))
    let green = CIImage(color: .green).cropped(to: CGRect(x: 100, y: 50, width: 100, height: 50))
    let blue = CIImage(color: .blue).cropped(to: CGRect(x: 0, y: 0, width: 100, height: 50))
    let white = CIImage(color: .white).cropped(to: CGRect(x: 100, y: 0, width: 100, height: 50))
    let sheet = red.composited(over: green).composited(over: blue).composited(over: white)
    let skewed = [CGPoint(x: 20, y: 10), CGPoint(x: 190, y: 5), CGPoint(x: 180, y: 95), CGPoint(x: 10, y: 80)]
    guard let output = ImageDeskewEngine.correct(sheet, quad: skewed, to: CGSize(width: 40, height: 20)) else {
        Issue.record("no corrected image"); return
    }
    #expect(abs(output.extent.width - 40) < 1 && abs(output.extent.height - 20) < 1)
    let context = CIContext(options: [.workingColorSpace: NSNull()])
    let sample = { (x: CGFloat, y: CGFloat) -> [UInt8] in
        var pixel = [UInt8](repeating: 0, count: 4)
        // y counts from top
        let at = CGRect(x: output.extent.minX + x, y: output.extent.maxY - 1 - y, width: 1, height: 1)
        context.render(output, toBitmap: &pixel, rowBytes: 4, bounds: at, format: .RGBA8, colorSpace: nil)
        return Array(pixel.prefix(3))
    }
    #expect(sample(3, 3) == [255, 0, 0], "top left")
    #expect(sample(36, 3) == [0, 255, 0], "top right")
    #expect(sample(3, 16) == [0, 0, 255], "bottom left")
    #expect(sample(36, 16) == [255, 255, 255], "bottom right")
    #expect(ImageDeskewEngine.correct(sheet, quad: Array(skewed.reversed()), to: CGSize(width: 40, height: 20)) == nil)
}


@Test func metadataStrip() {
    let secrets = ["SecretLens", "SecretSerial", "SecretArtist", "SecretCity", "SecretTool", "SecretTitle"]
    let properties: [CFString: Any] = [
        kCGImagePropertyOrientation: 6,
        kCGImagePropertyDPIWidth: 300,
        kCGImagePropertyDPIHeight: 300,
        kCGImagePropertyExifDictionary: [
            kCGImagePropertyExifLensModel: secrets[0],
            kCGImagePropertyExifBodySerialNumber: secrets[1],
        ],
        kCGImagePropertyGPSDictionary: [
            kCGImagePropertyGPSLatitude: 49.0, kCGImagePropertyGPSLatitudeRef: "N",
            kCGImagePropertyGPSLongitude: 8.4, kCGImagePropertyGPSLongitudeRef: "E",
        ],
        kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFArtist: secrets[2], kCGImagePropertyTIFFMake: "Apple"],
        kCGImagePropertyIPTCDictionary: [kCGImagePropertyIPTCCity: secrets[3]],
        kCGImagePropertyMakerAppleDictionary: ["1": 14],
        kCGImagePropertyPNGDictionary: [kCGImagePropertyPNGTitle: secrets[5]],
    ]
    let xmp = CGImageMetadataCreateMutable()
    CGImageMetadataSetValueWithPath(xmp, nil, "xmp:CreatorTool" as CFString, secrets[4] as CFString)

    guard let context = CGContext(
        data: nil, width: 8, height: 4, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    ), let pixels = context.makeImage() else { Issue.record("no fixture bitmap"); return }

    for type in [UTType.jpeg, .heic, .png] {
        let plain = NSMutableData()
        // simulator may lack heic
        guard let first = CGImageDestinationCreateWithData(plain, type.identifier as CFString, 1, nil) else { continue }
        CGImageDestinationAddImage(first, pixels, properties as CFDictionary)
        guard CGImageDestinationFinalize(first),
              let plainSource = CGImageSourceCreateWithData(plain, nil) else { continue }

        let tagged = NSMutableData()
        let merge = [kCGImageDestinationMetadata: xmp, kCGImageDestinationMergeMetadata: true] as CFDictionary
        guard let second = CGImageDestinationCreateWithData(tagged, type.identifier as CFString, 1, nil),
              CGImageDestinationCopyImageSource(second, plainSource, merge, nil) else { continue }
        let fixture = tagged as Data

        let before = MetadataStripEngine.report(for: fixture)
        #expect(before.entries.contains { $0.isLocation }, "\(type.identifier): fixture has no GPS")
        #expect(before.entries.contains { $0.label == "XMP packet" })

        guard let stripped = MetadataStripEngine.strip(fixture) else { Issue.record("\(type.identifier): strip failed"); return }
        #expect(stripped.removed.contains("GPS") && stripped.removed.contains("XMP"))
        for secret in secrets {
            #expect(!MetadataStripEngine.contains(stripped.data, secret), "\(type.identifier): \(secret) survived")
        }
        #expect(!MetadataStripEngine.hasXMP(stripped.data))

        let source = CGImageSourceCreateWithData(stripped.data as CFData, nil)
        let after = source.flatMap { CGImageSourceCopyPropertiesAtIndex($0, 0, nil) as? [CFString: Any] } ?? [:]
        for key in [kCGImagePropertyGPSDictionary, kCGImagePropertyIPTCDictionary,
                    kCGImagePropertyMakerAppleDictionary, kCGImagePropertyExifAuxDictionary] {
            #expect(after[key] == nil, "\(type.identifier): \(key) survived")
        }
        let structural: Set<String> = [
            "ColorSpace", "PixelXDimension", "PixelYDimension", "Orientation", "TileLength", "TileWidth",
            "XResolution", "YResolution", "ResolutionUnit", "InterlaceType", "XPixelsPerMeter", "YPixelsPerMeter",
            "Gamma", "Chromaticities", "sRGBIntent",
        ]
        for key in [kCGImagePropertyExifDictionary, kCGImagePropertyTIFFDictionary, kCGImagePropertyPNGDictionary] {
            let names = (after[key] as? [CFString: Any] ?? [:]).keys.map { $0 as String }
            #expect(structural.isSuperset(of: names), "\(type.identifier): \(names) in \(key)")
        }
        #expect(after[kCGImagePropertyOrientation] as? Int == 6, "\(type.identifier): orientation lost")
        #expect(MetadataStripEngine.report(for: stripped.data).entries.allSatisfy { $0.label == String(localized: "Colour profile") })
    }

    #expect(MetadataStripEngine.strip(Data("not an image".utf8)) == nil)
}


@Test func metadataScan() throws {
    let properties: [CFString: Any] = [
        kCGImagePropertyExifDictionary: [kCGImagePropertyExifLensModel: "Lens"],
        kCGImagePropertyGPSDictionary: [
            kCGImagePropertyGPSLatitude: 33.9, kCGImagePropertyGPSLatitudeRef: "S",
            kCGImagePropertyGPSLongitude: 151.2, kCGImagePropertyGPSLongitudeRef: "E",
        ],
        kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFMake: "Apple"],
    ]
    let context = try #require(CGContext(
        data: nil, width: 8, height: 4, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    ))
    let pixels = try #require(context.makeImage())
    let tagged = NSMutableData()
    let destination = try #require(CGImageDestinationCreateWithData(tagged, "public.jpeg" as CFString, 1, nil))
    CGImageDestinationAddImage(destination, pixels, properties as CFDictionary)
    #expect(CGImageDestinationFinalize(destination))

    let found = MetadataScan(tagged as Data)
    #expect(found.blocks.isSuperset(of: [.exif, .gps, .tiff]), "\(found.blocks)")
    #expect(found.location == MetadataScan.Location(latitude: -33.9, longitude: 151.2))
    #expect(MetadataScan.label(found.location!) == "33.9000° S, 151.2000° E")

    let stripped = try #require(MetadataStripEngine.strip(tagged as Data))
    let left = MetadataScan(stripped.data)
    #expect(left.blocks.isDisjoint(with: [.exif, .gps, .tiff]) && left.location == nil, "\(left.blocks)")
}

@Test func svgMarkup() {
    let svg = "<?xml version=\"1.0\"?><svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 24 12\" stroke-width=\"3\">"
        + "<!-- a > b --><g><path d=\"" + String(repeating: "M 1 2 ", count: 40) + "\"/><text>Hi</text></g></svg>"
    #expect(SVGMarkup.looksLikeSVG("  \n<svg/>") && !SVGMarkup.looksLikeSVG("svg"))
    #expect(SVGMarkup.size(of: svg) == CGSize(width: 24, height: 12), "viewbox wins")
    #expect(SVGMarkup.size(of: "<svg stroke-width=\"2\" width=\"30px\" height='20'>") == CGSize(width: 30, height: 20), "width, not stroke-width")
    let lines = SVGMarkup.outline(svg).components(separatedBy: "\n")
    #expect(lines.count == 10, "a line per tag and text run: \(lines)")
    #expect(lines[2] == "  <!-- a > b -->" && lines[4].hasPrefix("    <path d=\"M 1 2") && lines[4].hasSuffix("…\"/>"), "\(lines)")
    #expect(lines[6] == "      Hi" && lines[7] == "    </text>" && lines[9] == "</svg>", "\(lines)")
    let many = "<svg>" + String(repeating: "<rect/>", count: SVGMarkup.lineLimit + 5) + "</svg>"
    #expect(SVGMarkup.outline(many).components(separatedBy: "\n").count == SVGMarkup.lineLimit + 1, "capped, with a count")
    #expect(SVGMarkup.sizedForScaling("<svg width=\"20px\" height='10'><rect/></svg>").contains("viewBox=\"0 0 20.0 10.0\""), "viewBox added")
    #expect(SVGMarkup.sizedForScaling("<svg viewBox=\"0 0 5 5\" width=\"20\">") == "<svg viewBox=\"0 0 5 5\" width=\"20\">", "kept")
    #expect(SVGMarkup.sizedForScaling("<svg stroke-width=\"2\">") == "<svg stroke-width=\"2\">", "no SVGMarkup.size, unchanged")
}


@Test func traceVectors() {
    let svg = "<svg width=\"20\" height=\"10\" version=\"1.1\" xmlns=\"http://www.w3.org/2000/svg\" desc=\"Created with imagetracer.js version 1.2.6\" >"
        + "<path fill=\"rgb(255,0,0)\" stroke=\"rgb(255,0,0)\" stroke-width=\"1\" opacity=\"1\" d=\"M 0 0 L 20 0 L 20 10 L 0 10 L 0 0 Z M 5 2 L 5 8 L 15 8 L 15 2 L 5 2 Z \" />"
        + "<path fill=\"rgb(0,0,255)\" stroke=\"rgb(0,0,255)\" stroke-width=\"1\" opacity=\"1\" d=\"M 5 2 Q 10 0 15 2 L 15 8 L 5 8 Z \" />"
        + "<path fill=\"rgb(255,0,0)\" stroke=\"rgb(255,0,0)\" stroke-width=\"1\" opacity=\"1\" d=\"M 9 4 L 11 4 L 11 6 Z \" />"
        + "<path fill=\"rgb(0,0,0)\" stroke=\"rgb(0,0,0)\" stroke-width=\"1\" opacity=\"0\" d=\"M 0 0 L 1 0 L 1 1 Z \" /></svg>"
    guard let vectors = TraceVectors.parse(svg) else { Issue.record("parses"); return }
    #expect(vectors.size == CGSize(width: 20, height: 10))
    #expect(vectors.layers.count == 3 && vectors.paths == 4, "one layer per fill, in order")
    #expect(vectors.layers[0].paths == 2 && vectors.layers[0].red == 255 && vectors.layers[1].blue == 255)
    #expect(vectors.lineCount == 14 && vectors.curveCount == 1, "\(vectors.lineCount) \(vectors.curveCount)")
    #expect(vectors.palette.count == 2, "transparent layers draw nothing")
    #expect(vectors.layers[0].fill.contains(CGPoint(x: 2, y: 5)) && !vectors.layers[0].fill.contains(CGPoint(x: 7, y: 5)), "hole")
    #expect(vectors.layers[0].fill.contains(CGPoint(x: 10.5, y: 4.5)), "island in the hole")
    #expect(TraceVectors.parse("<path d=\"M 0 0\"/>") == nil, "needs a size")
    let alphas = "<svg width=\"4\" height=\"4\"><path fill=\"rgb(9,9,9)\" opacity=\"1\" d=\"M 0 0 L 1 0 Z\"/><path fill=\"rgb(9,9,9)\" opacity=\"0.5\" d=\"M 2 2 L 3 2 Z\"/></svg>"
    #expect(TraceVectors.parse(alphas)?.layers.map(\.opacity) == [1, 0.5], "same RGB, different alpha: two layers")
    guard let image = vectors.render(pixels: CGSize(width: 40, height: 20), ink: nil, checks: (CGColor(gray: 1, alpha: 1), CGColor(gray: 0.9, alpha: 1))) else { Issue.record("renders"); return }
    #expect(image.width == 40 && image.height == 20)
}


@Test func foregroundCutout() throws {
    let map: [UInt8] = [1, 0, 0, 2,
                        1, 0, 0, 2]
    let labels = try #require(CGImage(width: 4, height: 2, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: 4, space: CGColorSpaceCreateDeviceGray(),
                                      bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue), provider: CGDataProvider(data: Data(map) as CFData)!,
                                      decode: nil, shouldInterpolate: false, intent: .defaultIntent))
    let context = try #require(CGContext(data: nil, width: 40, height: 20, bitsPerComponent: 8, bytesPerRow: 0,
                                         space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: 40, height: 20))
    let cutout = try ForegroundCutout(source: try #require(context.makeImage()), labels: labels)
    #expect(cutout.instances == IndexSet([1, 2]))
    #expect(cutout.instance(at: CGPoint(x: 0.1, y: 0.5)) == 1)
    #expect(cutout.instance(at: CGPoint(x: 0.5, y: 0.5)) == nil)
    #expect(cutout.instance(at: CGPoint(x: 0.99, y: 0.99)) == 2)
    #expect(cutout.share(of: [1]) == 0.25 && cutout.share(of: [1, 2]) == 0.5)
    let image = try #require(try cutout.render(keeping: [1], fill: nil))
    let data = try #require(image.dataProvider?.data as Data?)
    #expect(image.width == 40 && image.height == 20)
    let alpha = { (x: Int, y: Int) -> UInt8 in
        let offset = y * image.bytesPerRow + x * image.bitsPerPixel / 8
        return image.alphaInfo == .premultipliedFirst || image.alphaInfo == .first ? data[offset] : data[offset + 3]
    }
    #expect(alpha(2, 10) > 200 && alpha(37, 10) < 50, "\(alpha(2, 10)) \(alpha(37, 10))")
}

@Test func encodeEveryFormat() throws {
    let context = try #require(CGContext(data: nil, width: 8, height: 6, bitsPerComponent: 8, bytesPerRow: 0,
                                         space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: 4, height: 6))
    let image = try #require(context.makeImage())
    for format in ImageOutputFormat.allCases {
        let flatten = format.supportsTransparency ? nil : CGColor(gray: 1, alpha: 1)
        let data = try #require(format.encode(image, width: 16, height: 12, quality: 0.8, flatten: flatten), "\(format)")
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        #expect(CGImageSourceGetType(source) as String? == format.utType.identifier, "\(format)")
        let decoded = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(decoded.width == 16 && decoded.height == 12, "\(format)")
    }
    #expect(ImageOutputFormat.jpeg.fileExtension == "jpg" && ImageOutputFormat.png.label == "PNG")
}

@Test func splitSourceDecodesUpright() throws {
    let context = try #require(CGContext(data: nil, width: 40, height: 20, bitsPerComponent: 8, bytesPerRow: 0,
                                         space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("split-\(UUID().uuidString).jpg")
    defer { try? FileManager.default.removeItem(at: url) }
    let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil))
    // exif 6: shown turned a quarter, 20 × 40
    CGImageDestinationAddImage(destination, try #require(context.makeImage()), [kCGImagePropertyOrientation: 6] as CFDictionary)
    #expect(CGImageDestinationFinalize(destination))
    let source = try #require(SplitSource.decode(url, maxPixels: 30, previewPixels: 10))
    #expect(source.pixels == (20, 40) && source.stem.hasPrefix("split-"))
    #expect(source.image.width == 15 && source.image.height == 30 && source.preview.height == 10)
}

@Test func imageToolEngines() {
    ImageCompressEngine.selfCheck()
    PNGChunkStrip.selfCheck()
    PlaceholderSpec.selfCheck()
    FaviconEngine.selfCheck()
    Base64Image.selfCheck()
}
