import AVFoundation
import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

// port of lib/gif.ts
// ponytail: opaque RGB565 at 256 colours only, which is all video-to-gif uses; rgb444, rgba4444 and single-image encodeGif are not ported
/// Animated GIF writer: a header, frames quantised to 256 colours by median cut, LZW-packed, then the trailer.
public enum GIFEncoder: Sendable {

    public static let trailer: [UInt8] = [0x3b]

    public static func header(width: Int, height: Int) -> [UInt8] {
        var out: [UInt8] = Array("GIF89a".utf8)
        out += [UInt8(width & 0xff), UInt8(width >> 8), UInt8(height & 0xff), UInt8(height >> 8), 7 << 4, 0, 0]
        out += [0x21, 0xff, 0x0b] + Array("NETSCAPE2.0".utf8) + [0x03, 0x01, 0, 0, 0]
        return out
    }

    /// `rgba` is `width * height * 4` bytes; alpha is ignored.
    public static func frame(rgba: UnsafeBufferPointer<UInt8>, width: Int, height: Int, delayMs: Double) -> [UInt8] {
        let quantised = quantise(rgba, pixels: width * height)
        // browsers clamp under 20ms
        let delay = max(2, Int((delayMs / 10).rounded()))
        var out: [UInt8] = [0x21, 0xf9, 0x04, 1 << 2, UInt8(delay & 0xff), UInt8(delay >> 8), 0, 0]
        let sizeField = UInt8(quantised.tableSize.trailingZeroBitCount - 1)
        out += [0x2c, 0, 0, 0, 0,
                UInt8(width & 0xff), UInt8(width >> 8), UInt8(height & 0xff), UInt8(height >> 8),
                0x80 | sizeField]
        out += quantised.palette
        out += [UInt8](repeating: 0, count: quantised.tableSize * 3 - quantised.palette.count)

        let minCodeSize = quantised.tableSize.trailingZeroBitCount
        out.append(UInt8(minCodeSize))
        let data = lzw(quantised.indices, minCodeSize: minCodeSize)
        var offset = 0
        while offset < data.count {
            let end = min(offset + 255, data.count)
            out.append(UInt8(end - offset))
            out += data[offset..<end]
            offset = end
        }
        out.append(0)
        return out
    }

    private struct Bucket {
        var r, g, b: Int
        var count: Int

        func channel(_ axis: Int) -> Int { axis == 0 ? r : axis == 1 ? g : b }
    }

    private struct Box {
        var buckets: [Bucket]
        var axis = 0
        var spread = 0
        var weight = 0

        init(_ buckets: [Bucket]) {
            self.buckets = buckets
            guard var lo = buckets.first else { return }
            var hi = lo
            for bucket in buckets {
                weight += bucket.count
                if bucket.r < lo.r { lo.r = bucket.r } else if bucket.r > hi.r { hi.r = bucket.r }
                if bucket.g < lo.g { lo.g = bucket.g } else if bucket.g > hi.g { hi.g = bucket.g }
                if bucket.b < lo.b { lo.b = bucket.b } else if bucket.b > hi.b { hi.b = bucket.b }
            }
            for a in 0..<3 where hi.channel(a) - lo.channel(a) > spread {
                spread = hi.channel(a) - lo.channel(a)
                axis = a
            }
        }
    }

    private static func medianCut(_ buckets: [Bucket], target: Int) -> [Box] {
        var boxes = [Box(buckets)]
        while boxes.count < target {
            var chosen = -1
            var widest = 0
            for (i, box) in boxes.enumerated() where box.buckets.count >= 2 && box.spread > widest {
                widest = box.spread
                chosen = i
            }
            if chosen < 0 { break }

            let axis = boxes[chosen].axis
            let box = boxes[chosen].buckets.sorted { $0.channel(axis) < $1.channel(axis) }
            let total = boxes[chosen].weight
            var seen = 0
            var split = 1
            for i in 0..<(box.count - 1) {
                seen += box[i].count
                if seen * 2 >= total {
                    split = i + 1
                    break
                }
            }
            boxes.replaceSubrange(chosen...chosen, with: [Box(Array(box[..<split])), Box(Array(box[split...]))])
        }
        return boxes
    }

    private static func key(_ rgba: UnsafeBufferPointer<UInt8>, _ pixel: Int) -> Int {
        let i = pixel * 4
        return (Int(rgba[i]) >> 3) << 11 | (Int(rgba[i + 1]) >> 2) << 5 | Int(rgba[i + 2]) >> 3
    }

    private static func quantise(_ rgba: UnsafeBufferPointer<UInt8>, pixels: Int)
        -> (palette: [UInt8], indices: [UInt8], tableSize: Int) {
        var counts = [Int](repeating: 0, count: 1 << 16)
        // for-in is slow unoptimised
        var p = 0
        while p < pixels {
            counts[key(rgba, p)] += 1
            p += 1
        }

        var buckets: [Bucket] = []
        var colour = 0
        while colour < counts.count {
            if counts[colour] > 0 {
                buckets.append(Bucket(r: (colour >> 11) << 3, g: ((colour >> 5) & 0x3f) << 2, b: (colour & 0x1f) << 3,
                                      count: counts[colour]))
            }
            colour += 1
        }
        let boxes = medianCut(buckets.isEmpty ? [Bucket(r: 0, g: 0, b: 0, count: 1)] : buckets, target: 256)

        var palette: [UInt8] = []
        var colourToIndex = [UInt8](repeating: 0, count: 1 << 16)
        for (index, box) in boxes.enumerated() {
            var (r, g, b) = (0, 0, 0)
            for bucket in box.buckets {
                r += bucket.r * bucket.count
                g += bucket.g * bucket.count
                b += bucket.b * bucket.count
                colourToIndex[(bucket.r >> 3) << 11 | (bucket.g >> 2) << 5 | bucket.b >> 3] = UInt8(index)
            }
            let mean = { (sum: Int) in UInt8((Double(sum) / Double(box.weight)).rounded()) }
            palette += [mean(r), mean(g), mean(b)]
        }

        // gif minimum code size
        var tableSize = 4
        while tableSize < boxes.count { tableSize *= 2 }

        var indices = [UInt8](repeating: 0, count: pixels)
        p = 0
        while p < pixels {
            indices[p] = colourToIndex[key(rgba, p)]
            p += 1
        }
        return (palette, indices, tableSize)
    }

    private static let maxCode = 4096

    private struct BitWriter {
        var bytes: [UInt8] = []
        private var accumulator = 0
        private var bits = 0

        mutating func emit(_ code: Int, size: Int) {
            accumulator |= code << bits
            bits += size
            while bits >= 8 {
                bytes.append(UInt8(accumulator & 0xff))
                accumulator >>= 8
                bits -= 8
            }
        }

        mutating func flush() {
            if bits > 0 { bytes.append(UInt8(accumulator & 0xff)) }
            bits = 0
        }
    }

    private static func lzw(_ indices: [UInt8], minCodeSize: Int) -> [UInt8] {
        let clearCode = 1 << minCodeSize
        let endCode = clearCode + 1
        var out = BitWriter()
        out.bytes.reserveCapacity(indices.count / 2)

        var codeSize = minCodeSize + 1
        var next = endCode + 1
        var table = [Int16](repeating: -1, count: maxCode << 8)
        var assignedKeys: [Int] = []
        assignedKeys.reserveCapacity(maxCode)

        out.emit(clearCode, size: codeSize)
        var prefix = indices.first.map(Int.init) ?? endCode
        // for-in is slow unoptimised
        var i = 1
        while i < indices.count {
            let suffix = Int(indices[i])
            i += 1
            let key = prefix << 8 | suffix
            let known = table[key]
            if known >= 0 {
                prefix = Int(known)
                continue
            }
            out.emit(prefix, size: codeSize)
            if next == maxCode {
                out.emit(clearCode, size: codeSize)
                for key in assignedKeys { table[key] = -1 }
                assignedKeys.removeAll(keepingCapacity: true)
                next = endCode + 1
                codeSize = minCodeSize + 1
            } else {
                table[key] = Int16(next)
                assignedKeys.append(key)
                next += 1
                if next > 1 << codeSize, codeSize < 12 { codeSize += 1 }
            }
            prefix = suffix
        }
        out.emit(prefix, size: codeSize)
        if !indices.isEmpty { out.emit(endCode, size: codeSize) }
        out.flush()
        return out.bytes
    }
}

#if DEBUG
extension GIFEncoder {
    private static func encode(_ frames: [[UInt8]], width: Int, height: Int, delayMs: Double) -> [UInt8] {
        var bytes = header(width: width, height: height)
        for rgba in frames {
            bytes += rgba.withUnsafeBufferPointer { frame(rgba: $0, width: width, height: height, delayMs: delayMs) }
        }
        return bytes + trailer
    }

    // 0x2c occurs in data
    private static func walk(_ bytes: [UInt8]) -> (extensions: [UInt8], frames: Int, trailed: Bool) {
        var (extensions, frames, i): ([UInt8], Int, Int) = ([], 0, 13)
        func skipSubBlocks() {
            while bytes[i] != 0 { i += Int(bytes[i]) + 1 }
            i += 1
        }
        while i < bytes.count {
            switch bytes[i] {
            case 0x3b: return (extensions, frames, true)
            case 0x21:
                extensions.append(bytes[i + 1])
                i += 2
                skipSubBlocks()
            case 0x2c:
                frames += 1
                let flags = bytes[i + 9]
                i += 10
                if flags & 0x80 != 0 { i += 3 * (2 << Int(flags & 0x07)) }
                i += 1
                skipSubBlocks()
            default:
                assertionFailure("unknown block")
                return (extensions, frames, false)
            }
        }
        return (extensions, frames, false)
    }

    private static func unlzw(_ data: [UInt8], minCodeSize: Int) -> [UInt8] {
        let clearCode = 1 << minCodeSize
        var table: [[UInt8]] = []
        var previous: [UInt8]?
        var (out, size, accumulator, bits): ([UInt8], Int, Int, Int) = ([], 0, 0, 0)
        func reset() {
            table = (0..<clearCode).map { [UInt8($0)] } + [[], []]
            size = minCodeSize + 1
            previous = nil
        }
        reset()
        for byte in data {
            accumulator |= Int(byte) << bits
            bits += 8
            while bits >= size {
                let code = accumulator & ((1 << size) - 1)
                accumulator >>= size
                bits -= size
                if code == clearCode {
                    reset()
                    continue
                }
                if code == clearCode + 1 { return out }
                guard let entry = code < table.count ? table[code] : previous.map({ $0 + [$0[0]] }) else { return [] }
                out += entry
                if let previous, table.count < maxCode { table.append(previous + [entry[0]]) }
                if table.count == 1 << size, size < 12 { size += 1 }
                previous = entry
            }
        }
        return out
    }

    public static func selfCheck() {
        var seed: UInt32 = 1
        let noise = (0..<20000).map { _ -> UInt8 in
            seed = seed &* 1664525 &+ 1013904223
            return UInt8(seed >> 24)
        }
        // past 4096 codes
        assert(unlzw(lzw(noise, minCodeSize: 8), minCodeSize: 8) == noise)
        let run = [UInt8](repeating: 3, count: 5000)
        assert(unlzw(lzw(run, minCodeSize: 2), minCodeSize: 2) == run)

        let red = [UInt8](repeating: 0, count: 16).enumerated().map { $0.offset % 4 == 0 || $0.offset % 4 == 3 ? UInt8(255) : 0 }
        let blue = [UInt8](repeating: 0, count: 16).enumerated().map { $0.offset % 4 >= 2 ? UInt8(255) : 0 }
        let bytes = encode([red, blue], width: 2, height: 2, delayMs: 100)
        assert(Array(bytes[0..<6]) == Array("GIF89a".utf8))
        assert(Array(bytes[6..<11]) == [2, 0, 2, 0, 7 << 4])
        assert(Array(bytes[16..<27]) == Array("NETSCAPE2.0".utf8))
        let structure = walk(bytes)
        assert(structure.frames == 2 && structure.trailed)
        assert(structure.extensions == [0xff, 0xf9, 0xf9])

        let clamped = encode([[0, 0, 0, 255]], width: 1, height: 1, delayMs: 5)
        assert(Array(clamped[32..<38]) == [0x21, 0xf9, 0x04, 1 << 2, 2, 0])
    }
}
#endif

public enum VideoFrames: Sendable {

    public enum Failure: Error { case tooManyFrames, encodeFailed }

    public static let maxGIFFrames = 300
    public static let sheetColumns = 4
    public static let sheetThumbWidth = 320
    public static let sheetLabelHeight = 22

    public static func gifFrameCount(start: Double, end: Double, fps: Int) -> Int {
        max(1, Int((abs(end - start) * Double(fps)).rounded()))
    }

    private static func generator(for url: URL, exact: Bool, maximumSize: CGSize = .zero) -> AVAssetImageGenerator {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = maximumSize
        if exact {
            generator.requestedTimeToleranceBefore = .zero
            generator.requestedTimeToleranceAfter = .zero
        }
        return generator
    }

    // failed frames retry once
    private static func forEachFrame(_ generator: AVAssetImageGenerator, at times: [CMTime],
                                     progress: MediaExport.Progress, _ body: (CGImage) throws -> Void) async throws {
        var done = 0
        defer { generator.cancelAllCGImageGeneration() }
        for await result in generator.images(for: times) {
            try Task.checkCancellation()
            if let image = try? result.image {
                try body(image)
            } else {
                try body(try await generator.image(at: result.requestedTime).image)
            }
            done += 1
            progress(Double(done) / Double(times.count))
        }
    }

    /// Width-bound frames, one per `1 / fps`, each quantised and written to disk before the next decodes.
    // imageio destination buffered 1GB
    @concurrent
    public static func gif(from video: URL, start: Double, end: Double, fps: Int, width: Int, to output: URL,
                    progress: @escaping MediaExport.Progress) async throws -> Int {
        let duration = try await AVURLAsset(url: video).load(.duration).seconds
        guard duration.isFinite else { throw Failure.encodeFailed }
        let from = min(max(0, min(start, end)), duration)
        let frames = gifFrameCount(start: from, end: min(max(start, end), duration), fps: fps)
        guard frames <= maxGIFFrames else { throw Failure.tooManyFrames }

        try? FileManager.default.removeItem(at: output)
        guard FileManager.default.createFile(atPath: output.path, contents: nil) else { throw Failure.encodeFailed }
        let handle = try FileHandle(forWritingTo: output)
        defer { try? handle.close() }

        // height 0: aspect kept
        let generator = generator(for: video, exact: true, maximumSize: CGSize(width: width, height: 0))
        let times = (0..<frames).map { MediaExport.time(from + Double($0) / Double(fps)) }
        let delayMs = 1000 / Double(fps)
        var canvas: CGContext?
        try await forEachFrame(generator, at: times, progress: progress) { image in
            if canvas == nil {
                canvas = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                                   bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                   bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
                try handle.write(contentsOf: GIFEncoder.header(width: image.width, height: image.height))
            }
            guard let canvas, let data = canvas.data else { throw Failure.encodeFailed }
            canvas.draw(image, in: CGRect(x: 0, y: 0, width: canvas.width, height: canvas.height))
            let rgba = UnsafeBufferPointer(start: data.assumingMemoryBound(to: UInt8.self),
                                           count: canvas.width * canvas.height * 4)
            try handle.write(contentsOf: GIFEncoder.frame(rgba: rgba, width: canvas.width,
                                                                height: canvas.height, delayMs: delayMs))
        }
        try handle.write(contentsOf: GIFEncoder.trailer)
        return frames
    }

    /// The exact frame at `time` written as PNG; returns the frame.
    @concurrent
    public static func still(from video: URL, at time: CMTime, to output: URL) async throws -> CGImage {
        let image = try await generator(for: video, exact: true).image(at: time).image
        try writePNG(image, to: output)
        return image
    }

    /// The middle of `count` equal spans, which keeps clear of the first and last frame.
    public static func sheetTimes(duration: Double, count: Int) -> [Double] {
        (0..<count).map { duration * (Double($0) + 0.5) / Double(count) }
    }

    /// `count` frames in rows of four, each labelled with its time, as one PNG.
    @concurrent
    public static func contactSheet(from video: URL, duration: Double, count: Int, to output: URL,
                                    progress: @escaping MediaExport.Progress) async throws {
        let columns = min(sheetColumns, count)
        let rows = Int((Double(count) / Double(max(1, columns))).rounded(.up))
        let thumbWidth = CGFloat(sheetThumbWidth)
        let generator = generator(for: video, exact: true, maximumSize: CGSize(width: thumbWidth, height: 0))
        let seconds = sheetTimes(duration: duration, count: count)

        var thumbs: [CGImage] = []
        try await forEachFrame(generator, at: seconds.map(MediaExport.time), progress: progress) { thumbs.append($0) }
        guard let first = thumbs.first else { throw Failure.encodeFailed }
        let thumbHeight = (thumbWidth * CGFloat(first.height) / CGFloat(first.width)).rounded()
        let size = CGSize(width: CGFloat(columns) * thumbWidth, height: CGFloat(rows) * thumbHeight)
        guard let context = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8,
                                      bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { throw Failure.encodeFailed }
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.fill(CGRect(origin: .zero, size: size))
        let labelHeight = CGFloat(sheetLabelHeight)
        let font = CTFontCreateUIFontForLanguage(.userFixedPitch, 13, nil) ?? CTFontCreateWithName("Menlo" as CFString, 13, nil)
        for (index, thumb) in thumbs.enumerated() {
            // bottom-left origin
            let cell = CGRect(x: CGFloat(index % columns) * thumbWidth,
                              y: size.height - CGFloat(index / columns + 1) * thumbHeight, width: thumbWidth, height: thumbHeight)
            context.draw(thumb, in: cell)
            context.setFillColor(CGColor(gray: 0, alpha: 0.6))
            context.fill(CGRect(x: cell.minX, y: cell.minY, width: thumbWidth, height: labelHeight))
            let label = NSAttributedString(string: MediaExport.timestamp(seconds[index]), attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): font,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 1, alpha: 1),
            ])
            let line = CTLineCreateWithAttributedString(label)
            context.textPosition = CGPoint(x: cell.minX + 8, y: cell.minY + (labelHeight - CTFontGetCapHeight(font)) / 2)
            CTLineDraw(line, context)
        }
        guard let sheet = context.makeImage() else { throw Failure.encodeFailed }
        try writePNG(sheet, to: output)
    }

    private static func writePNG(_ image: CGImage, to output: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(
            output as CFURL, UTType.png.identifier as CFString, 1, nil
        ) else { throw Failure.encodeFailed }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw Failure.encodeFailed }
    }
}

#if DEBUG
extension VideoFrames {
    public static func selfCheck() {
        assert(gifFrameCount(start: 0, end: 5, fps: 10) == 50)
        assert(gifFrameCount(start: 5, end: 0, fps: 10) == 50)
        assert(gifFrameCount(start: 1, end: 1, fps: 10) == 1)
        assert(gifFrameCount(start: 0, end: 30.1, fps: 10) > maxGIFFrames)
        assert(sheetTimes(duration: 12, count: 4) == [1.5, 4.5, 7.5, 10.5] && sheetTimes(duration: 12, count: 0).isEmpty)
    }
}
#endif

/// Video exports: the container a copy is written in, a muted copy, a trimmed copy.
extension MediaExport {
    public enum Container: String, CaseIterable, Identifiable, Sendable {
        case mp4, mov

        public var id: String { rawValue }
        public var label: String { rawValue.uppercased() }
        public var fileType: AVFileType { self == .mp4 ? .mp4 : .mov }

        public init(source: URL) {
            self = source.pathExtension.lowercased() == "mov" ? .mov : .mp4
        }
    }

    /// Every video track, no audio; passthrough first.
    @concurrent
    public static func mute(_ video: URL, container: Container, to output: URL, progress: @escaping Progress) async throws {
        let silent = try await composition(of: AVURLAsset(url: video), keeping: .video, firstOnly: false)
        guard !silent.tracks.isEmpty else { throw Failure.noVideo }
        try await export(silent, preset: AVAssetExportPresetPassthrough, fallback: AVAssetExportPresetHighestQuality,
                         as: container.fileType, to: output, progress: progress)
    }

    /// Re-encodes: a passthrough copy can only start on the sync sample at or before `range.lowerBound`.
    @concurrent
    public static func trim(_ video: URL, range: ClosedRange<Double>, container: Container, to output: URL,
                            progress: @escaping Progress) async throws {
        try await export(AVURLAsset(url: video), preset: AVAssetExportPresetHighestQuality, as: container.fileType,
                         range: CMTimeRange(start: time(range.lowerBound), end: time(range.upperBound)),
                         to: output, progress: progress)
    }
}
