import AVFoundation
import CoreGraphics
import Foundation
import Testing
@testable import DelphiCore

@Test func videoSelfChecks() {
    SubtitleCodec.selfCheck()
    GIFEncoder.selfCheck()
    VideoFrames.selfCheck()
    SubtitleBurnRenderer.selfCheck()
    if #available(macOS 26.0, iOS 26.0, *) { SubtitleTranscriber.selfCheck() }
}

/// One second of 64 × 48 frames, red to blue, at 10 fps.
private func sampleVideo(in folder: URL) async throws -> URL {
    let url = folder.appendingPathComponent("sample.mov")
    let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
    let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
        AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 64, AVVideoHeightKey: 48,
    ])
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: 64,
        kCVPixelBufferHeightKey as String: 48,
    ])
    writer.add(input)
    writer.startWriting()
    writer.startSession(atSourceTime: .zero)
    for frame in 0..<10 {
        while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(5)) }
        var buffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, try #require(adaptor.pixelBufferPool), &buffer)
        let pixels = try #require(buffer)
        CVPixelBufferLockBaseAddress(pixels, [])
        let base = try #require(CVPixelBufferGetBaseAddress(pixels)).assumingMemoryBound(to: UInt8.self)
        for i in stride(from: 0, to: CVPixelBufferGetBytesPerRow(pixels) * 48, by: 4) {
            (base[i], base[i + 1], base[i + 2], base[i + 3]) = (UInt8(frame * 25), 0, UInt8(255 - frame * 25), 255)
        }
        CVPixelBufferUnlockBaseAddress(pixels, [])
        adaptor.append(pixels, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: 10))
    }
    input.markAsFinished()
    await writer.finishWriting()
    #expect(writer.status == .completed)
    return url
}

@Test func videoExports() async throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("video-tests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let video = try await sampleVideo(in: folder)

    let gif = folder.appendingPathComponent("out.gif")
    let frames = try await VideoFrames.gif(from: video, start: 0, end: 0.5, fps: 10, width: 32, to: gif) { _ in }
    #expect(frames == 5)
    let source = try #require(CGImageSourceCreateWithURL(gif as CFURL, nil))
    #expect(CGImageSourceGetCount(source) == 5)
    #expect(CGImageSourceCreateImageAtIndex(source, 0, nil)?.width == 32)

    let sheet = folder.appendingPathComponent("sheet.png")
    try await VideoFrames.contactSheet(from: video, duration: 1, count: 6, to: sheet) { _ in }
    let image = try #require(CGImageSourceCreateWithURL(sheet as CFURL, nil).flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) })
    #expect(image.width == VideoFrames.sheetThumbWidth * 4)

    let still = try await VideoFrames.still(from: video, at: MediaExport.time(0.5), to: folder.appendingPathComponent("still.png"))
    #expect(still.width == 64)

    let trimmed = folder.appendingPathComponent("trim.mov")
    try await MediaExport.trim(video, range: 0.2...0.7, container: .mov, to: trimmed) { _ in }
    let length = try await AVURLAsset(url: trimmed).load(.duration).seconds
    #expect(abs(length - 0.5) < 0.15)

    let muted = folder.appendingPathComponent("mute.mov")
    try await MediaExport.mute(video, container: .mov, to: muted) { _ in }
    #expect(try await AVURLAsset(url: muted).loadTracks(withMediaType: .audio).isEmpty)

    let burnt = folder.appendingPathComponent("burnt.mp4")
    let cues = [SubtitleCue(start: 0, end: 600, text: "Hello")]
    try await SubtitleBurner.export(video: video, cues: cues, style: SubtitleBurnStyle(), codec: .h264, to: burnt) { _ in }
    #expect(try await AVURLAsset(url: burnt).load(.duration).seconds > 0.5)
}
