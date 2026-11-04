import Accelerate
import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Audio analysis shared by audio-atlas, waveform-genny and voice-recorder.
/// Reads in chunks, so a long file never lands in memory whole, and every entry
/// point honours cancellation of the task it runs on.
public enum AudioDSP: Sendable {

    public struct Peaks: Equatable, Sendable {
        public var min: [Float]
        public var max: [Float]

        public init(min: [Float], max: [Float]) {
            (self.min, self.max) = (min, max)
        }

        public static let empty = Peaks(min: [], max: [])
        public var isEmpty: Bool { min.isEmpty }
    }

    public struct Scan: Sendable {
        public var peaks: Peaks
        /// `-.infinity` when the range is digital silence.
        public var peakDb: Double
        public var rmsDb: Double
        /// `nil` when the range is shorter than one 400 ms gating block.
        public var lufs: Double?
        public var sampleRate: Double
        public var channelCount: Int
        public var duration: Double
    }

    public enum Failure: Error { case unreadable }

    private static let chunkFrames: AVAudioFrameCount = 1 << 15

    // MARK: - Scan

    public static func scan(
        url: URL,
        range: ClosedRange<Double>? = nil,
        buckets: Int,
        measureLoudness: Bool = false,
        progress: @Sendable (Double) -> Void = { _ in }
    ) throws -> Scan {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let sampleRate = format.sampleRate
        let channels = Int(format.channelCount)
        let totalFrames = file.length
        let duration = sampleRate > 0 ? Double(totalFrames) / sampleRate : 0
        guard channels > 0, totalFrames > 0, buckets > 0 else { throw Failure.unreadable }

        let start = clampFrame(range?.lowerBound ?? 0, sampleRate: sampleRate, limit: totalFrames)
        let end = max(start + 1, clampFrame(range?.upperBound ?? duration, sampleRate: sampleRate, limit: totalFrames))
        let span = end - start

        var lo = [Float](repeating: .infinity, count: buckets)
        var hi = [Float](repeating: -.infinity, count: buckets)
        var peak: Float = 0
        var squareSum: Double = 0
        var sampleCount: Double = 0

        var filters = measureLoudness
            ? (0..<channels).map { _ in kWeighting(sampleRate: sampleRate) }
            : []
        let subBlockFrames = Int((0.1 * sampleRate).rounded())
        var subBlockSums: [Double] = []
        var subBlockEnergy: Double = 0
        var subBlockFilled = 0

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunkFrames) else {
            throw Failure.unreadable
        }
        file.framePosition = start

        var consumed: AVAudioFramePosition = 0
        var reported = 0.0
        while consumed < span {
            try Task.checkCancellation()
            let want = AVAudioFrameCount(Swift.min(AVAudioFramePosition(chunkFrames), span - consumed))
            try file.read(into: buffer, frameCount: want)
            let got = Int(buffer.frameLength)
            guard got > 0, let data = buffer.floatChannelData else { break }

            for channel in 0..<channels {
                let whole = UnsafeBufferPointer(start: data[channel], count: got)
                peak = Swift.max(peak, vDSP.maximumMagnitude(whole))
                squareSum += Double(vDSP.sumOfSquares(whole))
            }
            sampleCount += Double(got * channels)

            var offset = 0
            while offset < got {
                let position = consumed + AVAudioFramePosition(offset)
                let bucket = Swift.min(buckets - 1, Int(position * AVAudioFramePosition(buckets) / span))
                let run = Swift.min(got - offset, Swift.max(1, Int(bucketStart(bucket + 1, span: span, buckets: buckets) - position)))
                for channel in 0..<channels {
                    let slice = UnsafeBufferPointer(start: data[channel] + offset, count: run)
                    lo[bucket] = Swift.min(lo[bucket], vDSP.minimum(slice))
                    hi[bucket] = Swift.max(hi[bucket], vDSP.maximum(slice))
                }
                offset += run
            }

            if measureLoudness, subBlockFrames > 0 {
                var energy = [Double](repeating: 0, count: got)
                for channel in 0..<channels {
                    let samples = UnsafeBufferPointer(start: data[channel], count: got)
                    var state = filters[channel]
                    for index in 0..<got {
                        let value = state.process(Double(samples[index]))
                        energy[index] += value * value
                    }
                    filters[channel] = state
                }

                var index = 0
                while index < got {
                    let take = Swift.min(subBlockFrames - subBlockFilled, got - index)
                    for position in index..<(index + take) { subBlockEnergy += energy[position] }
                    subBlockFilled += take
                    index += take
                    if subBlockFilled == subBlockFrames {
                        subBlockSums.append(subBlockEnergy)
                        subBlockEnergy = 0
                        subBlockFilled = 0
                    }
                }
            }

            consumed += AVAudioFramePosition(got)
            // per-chunk reports flood main
            let fraction = Double(consumed) / Double(span)
            if fraction - reported >= 0.01 || fraction >= 1 {
                reported = fraction
                progress(fraction)
            }
        }

        for bucket in 0..<buckets where lo[bucket] == .infinity {
            lo[bucket] = 0
            hi[bucket] = 0
        }

        let rms = sampleCount > 0 ? (squareSum / sampleCount).squareRoot() : 0
        return Scan(
            peaks: Peaks(min: lo, max: hi),
            peakDb: peak == 0 ? -.infinity : 20 * log10(Double(peak)),
            rmsDb: rms == 0 ? -.infinity : 20 * log10(rms),
            lufs: measureLoudness ? gatedLoudness(subBlockSums, subBlockFrames: subBlockFrames) : nil,
            sampleRate: sampleRate,
            channelCount: channels,
            duration: duration
        )
    }

    /// First frame of `bucket`, so bucket b covers `[start(b), start(b + 1))`.
    public static func bucketStart(_ bucket: Int, span: AVAudioFramePosition, buckets: Int) -> AVAudioFramePosition {
        let b = AVAudioFramePosition(buckets)
        return (AVAudioFramePosition(bucket) * span + b - 1) / b
    }

    private static func clampFrame(_ seconds: Double, sampleRate: Double, limit: AVAudioFramePosition) -> AVAudioFramePosition {
        let frame = AVAudioFramePosition((Swift.max(0, seconds) * sampleRate).rounded())
        return Swift.min(Swift.max(0, frame), limit)
    }

    /// Re-buckets a scan to a coarser width; returns it unchanged if it is already coarser.
    public static func resample(_ peaks: Peaks, to buckets: Int) -> Peaks {
        let source = peaks.min.count
        guard buckets > 0, source > 0 else { return .empty }
        if buckets >= source { return peaks }
        var lo = [Float](repeating: 0, count: buckets)
        var hi = [Float](repeating: 0, count: buckets)
        for bucket in 0..<buckets {
            let from = bucket * source / buckets
            let to = Swift.max(from + 1, (bucket + 1) * source / buckets)
            lo[bucket] = vDSP.minimum(peaks.min[from..<to])
            hi[bucket] = vDSP.maximum(peaks.max[from..<to])
        }
        return Peaks(min: lo, max: hi)
    }

    // MARK: - Loudness (BS.1770-4)

    private struct Biquad {
        public let b0, b1, b2, a1, a2: Double
        public var x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0

        public mutating func process(_ x: Double) -> Double {
            let y = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
            x2 = x1; x1 = x
            y2 = y1; y1 = y
            return y
        }
    }

    private struct KWeighting {
        public var shelf: Biquad
        public var highpass: Biquad

        public mutating func process(_ x: Double) -> Double {
            highpass.process(shelf.process(x))
        }
    }

    private static func kWeighting(sampleRate: Double) -> KWeighting {
        var f0 = 1681.974450955533
        var q = 0.7071752369554196
        let gainDb = 3.999843853973347
        var k = tan(.pi * f0 / sampleRate)
        let vh = pow(10, gainDb / 20)
        let vb = pow(vh, 0.4996667741545416)
        var a0 = 1 + k / q + k * k
        let shelf = Biquad(
            b0: (vh + (vb * k) / q + k * k) / a0,
            b1: (2 * (k * k - vh)) / a0,
            b2: (vh - (vb * k) / q + k * k) / a0,
            a1: (2 * (k * k - 1)) / a0,
            a2: (1 - k / q + k * k) / a0
        )

        f0 = 38.13547087602444
        q = 0.5003270373238773
        k = tan(.pi * f0 / sampleRate)
        a0 = 1 + k / q + k * k
        let highpass = Biquad(
            b0: 1, b1: -2, b2: 1,
            a1: (2 * (k * k - 1)) / a0,
            a2: (1 - k / q + k * k) / a0
        )

        return KWeighting(shelf: shelf, highpass: highpass)
    }

    // bs.1770-4: 400 ms blocks, 75 % overlap
    private static func gatedLoudness(_ subBlockSums: [Double], subBlockFrames: Int) -> Double? {
        guard subBlockSums.count >= 4, subBlockFrames > 0 else { return nil }
        let blockFrames = Double(subBlockFrames * 4)
        var energies: [Double] = []
        for start in 0...(subBlockSums.count - 4) {
            energies.append(subBlockSums[start..<(start + 4)].reduce(0, +) / blockFrames)
        }

        let loudness = { (energy: Double) in -0.691 + 10 * log10(energy) }
        let aboveAbsolute = energies.filter { loudness($0) > -70 }
        guard !aboveAbsolute.isEmpty else { return nil }

        let gate = loudness(aboveAbsolute.reduce(0, +) / Double(aboveAbsolute.count)) - 10
        let gated = energies.filter { loudness($0) > gate }
        guard !gated.isEmpty else { return nil }
        return loudness(gated.reduce(0, +) / Double(gated.count))
    }

    // MARK: - Spectrogram

    private static let fftSize = 1024
    private static let floorDb = -90.0

    public static func spectrogram(
        url: URL,
        range: ClosedRange<Double>? = nil,
        columns: Int = 512,
        rows: Int = 256
    ) throws -> CGImage {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let sampleRate = format.sampleRate
        let channels = Int(format.channelCount)
        let totalFrames = file.length
        guard channels > 0, totalFrames > Int64(fftSize), columns > 0, rows > 0 else {
            throw Failure.unreadable
        }
        let duration = Double(totalFrames) / sampleRate

        let start = clampFrame(range?.lowerBound ?? 0, sampleRate: sampleRate, limit: totalFrames)
        let end = max(start + AVAudioFramePosition(fftSize),
                      clampFrame(range?.upperBound ?? duration, sampleRate: sampleRate, limit: totalFrames))
        let span = end - start
        let hop = max(1, (span - AVAudioFramePosition(fftSize)) / AVAudioFramePosition(max(1, columns - 1)))

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(fftSize)) else {
            throw Failure.unreadable
        }

        let window = (0..<fftSize).map { 0.5 * (1 - cos(2 * .pi * Double($0) / Double(fftSize - 1))) }
        let binsPerRow = Double(fftSize / 2) / Double(rows)
        let palette = spectroPalette()
        var pixels = [UInt8](repeating: 255, count: columns * rows * 4)
        var block = [Double](repeating: 0, count: fftSize)

        for column in 0..<columns {
            try Task.checkCancellation()
            let position = start + AVAudioFramePosition(column) * hop
            guard position + AVAudioFramePosition(fftSize) <= totalFrames else { break }
            file.framePosition = position
            try file.read(into: buffer, frameCount: AVAudioFrameCount(fftSize))
            let got = Int(buffer.frameLength)
            guard got > 0, let data = buffer.floatChannelData else { break }

            for index in 0..<fftSize {
                if index >= got { block[index] = 0; continue }
                var sum = 0.0
                for channel in 0..<channels { sum += Double(data[channel][index]) }
                block[index] = sum / Double(channels) * window[index]
            }

            let magnitudes = fftMagnitudes(block)
            for row in 0..<rows {
                let bin = Int(Double(rows - 1 - row) * binsPerRow)
                let db = 20 * log10(Double(magnitudes[Swift.min(bin, magnitudes.count - 1)]) + 1e-12)
                let t = Swift.min(1, Swift.max(0, 1 - db / floorDb))
                let entry = Int((t * 255).rounded()) * 3
                let pixel = (row * columns + column) * 4
                pixels[pixel] = palette[entry]
                pixels[pixel + 1] = palette[entry + 1]
                pixels[pixel + 2] = palette[entry + 2]
            }
        }

        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let image = CGImage(
                  width: columns, height: rows,
                  bitsPerComponent: 8, bitsPerPixel: 32,
                  bytesPerRow: columns * 4,
                  space: CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                  provider: provider, decode: nil, shouldInterpolate: false,
                  intent: .defaultIntent
              )
        else { throw Failure.unreadable }
        return image
    }

    private static func spectroPalette() -> [UInt8] {
        let stops: [(Double, Double, Double)] = [(16, 18, 16), (46, 125, 50), (240, 255, 240)]
        var lut = [UInt8](repeating: 0, count: 256 * 3)
        for i in 0..<256 {
            let t = Double(i) / 255
            let segment = t < 0.5 ? 0 : 1
            let local = (t - Double(segment) * 0.5) * 2
            let from = stops[segment]
            let to = stops[segment + 1]
            lut[i * 3] = UInt8(from.0 + (to.0 - from.0) * local)
            lut[i * 3 + 1] = UInt8(from.1 + (to.1 - from.1) * local)
            lut[i * 3 + 2] = UInt8(from.2 + (to.2 - from.2) * local)
        }
        return lut
    }

    /// Radix-2 FFT; magnitudes of the first half only, empty unless the count is a power of two.
    public static func fftMagnitudes(_ samples: [Double]) -> [Float] {
        let n = samples.count
        guard n > 0, n & (n - 1) == 0 else { return [] }

        var re = samples
        var im = [Double](repeating: 0, count: n)

        var j = 0
        for i in 1..<n {
            var bit = n >> 1
            while j & bit != 0 {
                j ^= bit
                bit >>= 1
            }
            j ^= bit
            if i < j { re.swapAt(i, j) }
        }

        var length = 2
        while length <= n {
            let angle = -2 * Double.pi / Double(length)
            let wRe = cos(angle)
            let wIm = sin(angle)
            var i = 0
            while i < n {
                var curRe = 1.0
                var curIm = 0.0
                for k in 0..<(length / 2) {
                    let a = i + k
                    let b = a + length / 2
                    let tRe = re[b] * curRe - im[b] * curIm
                    let tIm = re[b] * curIm + im[b] * curRe
                    re[b] = re[a] - tRe
                    im[b] = im[a] - tIm
                    re[a] += tRe
                    im[a] += tIm
                    let nextRe = curRe * wRe - curIm * wIm
                    curIm = curRe * wIm + curIm * wRe
                    curRe = nextRe
                }
                i += length
            }
            length <<= 1
        }

        return (0..<(n / 2)).map { Float((re[$0] * re[$0] + im[$0] * im[$0]).squareRoot() / Double(n)) }
    }
}

#if DEBUG
extension AudioDSP {
    public static func selfCheck() {
        let n = 256
        let bin = 8
        let wave = (0..<n).map { sin(2 * .pi * Double(bin) * Double($0) / Double(n)) }
        let magnitudes = fftMagnitudes(wave)
        assert(magnitudes.count == n / 2)
        let loudest = magnitudes.enumerated().max { $0.element < $1.element }?.offset
        assert(loudest == bin)
        assert(fftMagnitudes([1, 2, 3]).isEmpty)

        let peaks = Peaks(min: [-1, -0.5, -0.25, 0], max: [1, 0.5, 0.25, 0])
        let halved = resample(peaks, to: 2)
        assert(halved.min == [-1, -0.25] && halved.max == [1, 0.25])
        assert(resample(peaks, to: 8).min.count == 4)

        // buckets tile the span
        for buckets in [1, 3, 1000] {
            for span: AVAudioFramePosition in [1, 7, 10_000, 172_800_000] {
                assert(bucketStart(0, span: span, buckets: buckets) == 0)
                assert(bucketStart(buckets, span: span, buckets: buckets) == span)
                for bucket in 0..<buckets {
                    let from = bucketStart(bucket, span: span, buckets: buckets)
                    assert(from <= bucketStart(bucket + 1, span: span, buckets: buckets))
                    guard span >= AVAudioFramePosition(buckets) else { continue }
                    assert(Int(from * AVAudioFramePosition(buckets) / span) == bucket)
                }
            }
        }
    }
}
#endif


/// Waveform drawing shared by the on-screen preview and the PNG/SVG exports.
public enum WaveformRender: Sendable {

    /// Bar rectangles inside a `width × height` box, never outside it: float audio
    /// carries samples past ±1, which would draw over the frame and out of the viewBox.
    public static func bars(_ peaks: AudioDSP.Peaks, width: Double, height: Double) -> [CGRect] {
        let columns = min(peaks.min.count, peaks.max.count)
        guard columns > 0, width > 0, height > 0 else { return [] }
        let mid = height / 2
        let barWidth = width / Double(columns)
        return (0..<columns).map { column in
            let top = mid - unit(peaks.max[column]) * mid
            let bottom = mid - unit(peaks.min[column]) * mid
            return CGRect(x: Double(column) * barWidth, y: top,
                          width: max(barWidth, 0.5), height: max(1, bottom - top))
        }
    }

    private static func unit(_ sample: Float) -> Double {
        sample.isFinite ? Double(min(1, max(-1, sample))) : 0
    }

    public static func png(
        _ peaks: AudioDSP.Peaks,
        width: Int,
        height: Int,
        wave: DelphiColour,
        background: DelphiColour
    ) -> Data? {
        guard width > 0, height > 0,
              let context = CGContext(
                  data: nil, width: width, height: height,
                  bitsPerComponent: 8, bytesPerRow: 0,
                  space: CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
              )
        else { return nil }

        // bar layout counts y downwards
        context.translateBy(x: 0, y: Double(height))
        context.scaleBy(x: 1, y: -1)
        context.setFillColor(background.waveformColour)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(wave.waveformColour)
        context.fill(bars(peaks, width: Double(width), height: Double(height)))

        guard let image = context.makeImage() else { return nil }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }

    public static func svg(
        _ peaks: AudioDSP.Peaks,
        width: Int,
        height: Int,
        wave: DelphiColour,
        background: DelphiColour
    ) -> String {
        let rects = bars(peaks, width: Double(width), height: Double(height))
            .map { rect in
                String(format: #"<rect x="%.2f" y="%.2f" width="%.2f" height="%.2f"/>"#,
                       rect.minX, rect.minY, rect.width, rect.height)
            }
            .joined()
        return """
        <svg xmlns="http://www.w3.org/2000/svg" width="\(width)" height="\(height)" \
        viewBox="0 0 \(width) \(height)">\
        <rect width="\(width)" height="\(height)" fill="\(background.hex)"/>\
        <g fill="\(wave.hex)">\(rects)</g></svg>
        """
    }
}


extension DelphiColour {
    fileprivate var waveformColour: CGColor {
        CGColor(red: r, green: g, blue: b, alpha: 1)
    }
}
