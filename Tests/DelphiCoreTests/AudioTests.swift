import AVFoundation
import Foundation
import Testing
@testable import DelphiCore

@Test func audioSelfChecks() {
    Timecode.selfCheck()
    AudioDSP.selfCheck()
    AudioRender.selfCheck()
    RecordedTake.selfCheck()
    MediaExport.selfCheck()
}

/// One second of a 440 Hz sine at half scale, 48 kHz mono, as a WAV in its own temp folder.
private func sine(seconds: Double = 1) throws -> URL {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let url = folder.appendingPathComponent("sine.wav")
    let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 1))
    let file = try AVAudioFile(forWriting: url, settings: AudioFormat.wav.settings(sampleRate: 48000, channels: 1),
                               commonFormat: .pcmFormatFloat32, interleaved: false)
    let frames = AVAudioFrameCount(48000 * seconds)
    let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames))
    buffer.frameLength = frames
    for index in 0..<Int(frames) { buffer.floatChannelData![0][index] = Float(0.5 * sin(2 * .pi * 440 * Double(index) / 48000)) }
    try file.write(from: buffer)
    return url
}

@Test func scanAndRender() throws {
    let url = try sine()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let scan = try AudioDSP.scan(url: url, buckets: 100, measureLoudness: true)
    #expect(abs(scan.duration - 1) < 0.001 && scan.channelCount == 1 && scan.peaks.min.count == 100)
    // half scale: -6 dBFS peak, -9 dBFS rms
    #expect(abs(scan.peakDb + 6.02) < 0.1 && abs(scan.rmsDb + 9.03) < 0.1)
    #expect(scan.lufs != nil)

    let plan = AudioRender.planGain(lufs: scan.lufs, peakDb: scan.peakDb, targetLufs: -14)
    let out = url.deletingLastPathComponent().appendingPathComponent("out.wav")
    try AudioRender.render(source: url, to: out, format: .wav, range: 0.25...0.75, gain: AudioRender.dbToGain(plan.gainDb), fadeIn: 0.1)
    let rendered = try AudioDSP.scan(url: out, buckets: 10)
    #expect(abs(rendered.duration - 0.5) < 0.001)
    #expect(abs(rendered.peakDb - plan.outPeakDb) < 0.2)
    // fade starts at silence
    #expect(rendered.peaks.max[0] < rendered.peaks.max[5])

    let image = try AudioDSP.spectrogram(url: url, columns: 16, rows: 8)
    #expect(image.width == 16 && image.height == 8)
    let svg = WaveformRender.svg(scan.peaks, width: 200, height: 50, wave: DelphiColour(r: 0, g: 0, b: 0), background: DelphiColour(r: 1, g: 1, b: 1))
    #expect(svg.hasPrefix("<svg") && svg.contains("#FFFFFF"))
    #expect(WaveformRender.png(scan.peaks, width: 200, height: 50, wave: DelphiColour(r: 0, g: 0, b: 0), background: DelphiColour(r: 1, g: 1, b: 1)) != nil)
}

@Test func takeSavesAsAudio() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    var take = RecordedTake(rate: 48000)
    take.append((0..<48000).map { Float(0.25 * sin(2 * .pi * 220 * Double($0) / 48000)) })
    let saved = try #require(take.save(to: folder.appendingPathComponent("take.m4a")))
    let scan = try AudioDSP.scan(url: saved, buckets: 10)
    #expect(abs(scan.duration - 1) < 0.05)
}

@Test func probeReadsAudio() async throws {
    let url = try sine()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let result = try await MediaProbe.probe(url: url)
    #expect(abs(result.duration - 1) < 0.001)
    #expect(result.sections.contains { $0.rows.contains { $0.label == "Sample rate" && $0.value == "48000 Hz" } })
}
