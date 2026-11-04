import Accelerate
import AVFoundation
import Foundation

public enum AudioFormat: String, CaseIterable, Identifiable, Sendable {
    case wav, m4a

    public var id: String { rawValue }
    public var label: String { self == .wav ? "WAV" : "M4A (AAC)" }

    public func settings(sampleRate: Double, channels: AVAudioChannelCount) -> [String: Any] {
        switch self {
        case .wav:
            [AVFormatIDKey: kAudioFormatLinearPCM,
             AVSampleRateKey: sampleRate,
             AVNumberOfChannelsKey: channels,
             AVLinearPCMBitDepthKey: 16,
             AVLinearPCMIsFloatKey: false,
             AVLinearPCMIsBigEndianKey: false]
        case .m4a:
            [AVFormatIDKey: kAudioFormatMPEG4AAC,
             AVSampleRateKey: sampleRate,
             AVNumberOfChannelsKey: channels]
        }
    }
}

/// Gain, trim and fades written to a new file; ports the web's audio.ts and normalise.ts.
public enum AudioRender: Sendable {

    public struct Plan: Equatable, Sendable {
        public var gainDb: Double
        public var limited: Bool
        public var outPeakDb: Double
    }

    public enum Failure: Error { case unreadable, emptyRange, tooLongForWav }

    // riff sizes are 32-bit
    public static func fitsWav(frames: Int, channels: Int) -> Bool {
        frames <= (Int(UInt32.max) - 44) / (2 * max(1, channels))
    }

    public typealias Progress = @Sendable (Double) -> Void

    private static let chunkFrames: AVAudioFrameCount = 1 << 15

    public static func planGain(lufs: Double?, peakDb: Double, targetLufs: Double, ceilingDb: Double = -1) -> Plan {
        guard let lufs, lufs.isFinite, peakDb.isFinite else {
            return Plan(gainDb: 0, limited: false, outPeakDb: peakDb)
        }
        let wanted = targetLufs - lufs
        let headroom = ceilingDb - peakDb
        let limited = wanted > headroom
        let gainDb = limited ? headroom : wanted
        return Plan(gainDb: gainDb, limited: limited, outPeakDb: peakDb + gainDb)
    }

    public static func dbToGain(_ db: Double) -> Float {
        Float(pow(10, db / 20))
    }

    /// `range` is in seconds, whole file when nil; gain then linear fades, as the web's `encodeWav` + `applyFades`.
    public static func render(
        source: URL,
        to destination: URL,
        format: AudioFormat,
        range: ClosedRange<Double>? = nil,
        gain: Float = 1,
        fadeIn: Double = 0,
        fadeOut: Double = 0,
        progress: Progress = { _ in }
    ) throws {
        let file = try AVAudioFile(forReading: source)
        let processing = file.processingFormat
        let rate = processing.sampleRate
        var from: AVAudioFramePosition = 0
        var to = file.length
        if let range {
            from = max(0, AVAudioFramePosition((range.lowerBound * rate).rounded(.down)))
            to = min(file.length, AVAudioFramePosition((range.upperBound * rate).rounded(.up)))
        }
        guard to - from >= 1 else { throw Failure.emptyRange }

        let total = Int(to - from)
        guard format != .wav || fitsWav(frames: total, channels: Int(processing.channelCount)) else {
            throw Failure.tooLongForWav
        }
        let inFrames = min(total, Int((fadeIn * rate).rounded()))
        let outFrames = min(total, Int((fadeOut * rate).rounded()))

        try? FileManager.default.removeItem(at: destination)
        let output = try AVAudioFile(
            forWriting: destination,
            settings: format.settings(sampleRate: rate, channels: processing.channelCount),
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )

        var written = 0
        try forEachChunk(of: file, frames: from..<to, progress: progress) { buffer in
            let count = Int(buffer.frameLength)
            for channel in mutablePointers(buffer) {
                var samples = channel
                if gain != 1 { vDSP.multiply(gain, channel, result: &samples) }
                for i in 0..<max(0, min(count, inFrames - written)) {
                    samples[i] *= Float(written + i) / Float(inFrames)
                }
                for i in min(count, max(0, total - outFrames - written))..<count {
                    samples[i] *= Float(total - 1 - written - i) / Float(outFrames)
                }
                vDSP.clip(channel, to: -1...1, result: &samples)
            }
            written += count
            try output.write(from: buffer)
        }
    }

    private static func forEachChunk(
        of file: AVAudioFile,
        frames: Range<AVAudioFramePosition>,
        progress: Progress,
        _ body: (AVAudioPCMBuffer) throws -> Void
    ) throws {
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: chunkFrames) else {
            throw Failure.unreadable
        }
        file.framePosition = frames.lowerBound
        let total = Double(max(1, frames.count))
        var reported = 0.0
        while file.framePosition < frames.upperBound {
            try Task.checkCancellation()
            let wanted = min(AVAudioFramePosition(chunkFrames), frames.upperBound - file.framePosition)
            try file.read(into: buffer, frameCount: AVAudioFrameCount(wanted))
            guard buffer.frameLength > 0 else { break }
            try body(buffer)
            // per-chunk reports flood main
            let fraction = Double(file.framePosition - frames.lowerBound) / total
            if fraction - reported >= 0.01 || fraction >= 1 {
                reported = fraction
                progress(fraction)
            }
        }
    }

    private static func mutablePointers(_ buffer: AVAudioPCMBuffer) -> [UnsafeMutableBufferPointer<Float>] {
        guard let data = buffer.floatChannelData else { return [] }
        return (0..<Int(buffer.format.channelCount)).map {
            UnsafeMutableBufferPointer(start: data[$0], count: Int(buffer.frameLength))
        }
    }
}

#if DEBUG
extension AudioRender {
    public static func selfCheck() {
        assert(planGain(lufs: -20, peakDb: -10, targetLufs: -14) == Plan(gainDb: 6, limited: false, outPeakDb: -4))
        assert(planGain(lufs: -20, peakDb: -3, targetLufs: -14) == Plan(gainDb: 2, limited: true, outPeakDb: -1))
        assert(planGain(lufs: nil, peakDb: -3, targetLufs: -14) == Plan(gainDb: 0, limited: false, outPeakDb: -3))
        assert(planGain(lufs: Double.nan, peakDb: -3, targetLufs: -14).gainDb == 0)
        assert(planGain(lufs: -20, peakDb: -.infinity, targetLufs: -14).gainDb == 0)
        assert(abs(dbToGain(-6) - 0.5012) < 0.001)
        assert(dbToGain(0) == 1)
        assert(fitsWav(frames: 48000 * 3600 * 6, channels: 2))
        assert(!fitsWav(frames: 48000 * 3600 * 7, channels: 2))
        assert(fitsWav(frames: 1, channels: 0))
    }
}
#endif

/// A take as it is held while recording: mono Int16 at the input's rate, with the peak of every `window` frames.
public struct RecordedTake: Sendable {
    /// Seconds of audio behind each entry of `peaks`.
    public static let peakInterval = 0.02
    /// Longest take held: an hour of Int16 at 48 kHz is 346 MB.
    public static let maxSeconds = 3600.0

    public let rate: Double
    public let window: Int
    public private(set) var samples: [Int16] = []
    public private(set) var peaks: [Float] = []
    /// Frame the next captured sample goes to; behind `samples.count` after a scrub back.
    public private(set) var head = 0

    public init(rate: Double) {
        self.rate = rate
        // no regrowth copies
        samples.reserveCapacity(Int(rate * Self.maxSeconds))
        window = max(1, Int((rate * Self.peakInterval).rounded()))
    }

    /// Records at the head: over what is held there after a scrub back, and on past the end.
    public mutating func append(_ floats: [Float]) {
        var ints = [Int16](repeating: 0, count: floats.count)
        vDSP.convertElements(of: vDSP.multiply(32767, vDSP.clip(floats, to: -1...1)), to: &ints, rounding: .towardNearestInteger)
        let end = head + ints.count
        let kept = min(ints.count, samples.count - head)
        samples.replaceSubrange(head ..< head + kept, with: ints[..<kept])
        samples += ints[kept...]
        let first = head / window
        head = end
        // only windows written
        for index in first ..< min(samples.count / window, (end + window - 1) / window) {
            let peak = Float(samples[index * window ..< (index + 1) * window].lazy.map { Int($0.magnitude) }.max() ?? 0) / 32768
            if index < peaks.count { peaks[index] = peak } else { peaks.append(peak) }
        }
    }

    public mutating func scrub(to seconds: Double) {
        head = min(max(0, Int((seconds * rate).rounded())), samples.count)
    }

    public var position: Double { Double(head) / rate }
    public var duration: Double { Double(samples.count) / rate }

    /// AAC, or uncompressed WAV beside it when the encoder fails, so the take is kept. Returns the file written.
    @discardableResult
    public func save(to url: URL) -> URL? {
        do {
            try write(to: url, settings: [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC), AVSampleRateKey: rate,
                AVNumberOfChannelsKey: 1, AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
            ])
            return url
        } catch {
            try? FileManager.default.removeItem(at: url)
            let wav = url.deletingPathExtension().appendingPathExtension("wav")
            try? write(to: wav, settings: [
                AVFormatIDKey: Int(kAudioFormatLinearPCM), AVSampleRateKey: rate, AVNumberOfChannelsKey: 1,
                AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false,
            ])
            return FileManager.default.fileExists(atPath: wav.path) ? wav : nil
        }
    }

    private func write(to url: URL, settings: [String: Any]) throws {
        let file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatInt16, interleaved: true)
        let chunk = AVAudioFrameCount(rate)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: chunk),
              let data = buffer.int16ChannelData else { return }
        var start = 0
        while start < samples.count {
            let count = min(Int(chunk), samples.count - start)
            samples.withUnsafeBufferPointer { data[0].update(from: $0.baseAddress! + start, count: count) }
            buffer.frameLength = AVAudioFrameCount(count)
            try file.write(from: buffer)
            start += count
        }
    }

    #if DEBUG
    public static func selfCheck() {
        var held = RecordedTake(rate: 1000)
        precondition(held.window == 20)
        // fold crosses buffer edges
        held.append([Float](repeating: 0.5, count: 30))
        held.append([Float](repeating: -0.25, count: 20))
        precondition(held.peaks.count == 2 && held.samples.count == 50 && held.head == 50)
        precondition(abs(held.peaks[0] - 0.5) < 0.001 && abs(held.peaks[1] - 0.5) < 0.001)
        held.append([Float](repeating: 0, count: 10))
        precondition(held.peaks.count == 3 && abs(held.peaks[2] - 0.25) < 0.001)
        // punch-in overwrites tail
        held.scrub(to: 0.045)
        precondition(held.head == 45 && abs(held.position - 0.045) < 0.0001)
        held.append([Float](repeating: 1, count: 10))
        precondition(held.samples.count == 60 && held.peaks.count == 3 && held.peaks[2] > 0.999 && held.head == 55)
        held.append([Float](repeating: 0, count: 5))
        precondition(held.samples.count == 60 && held.head == 60 && held.peaks[2] > 0.999)
        // clamps both ends
        held.scrub(to: -1)
        precondition(held.head == 0)
        held.scrub(to: 9)
        precondition(held.head == 60)
        // clipping
        held.append([2, -2])
        precondition(Array(held.samples.suffix(2)) == [32767, -32767])
    }
    #endif
}
