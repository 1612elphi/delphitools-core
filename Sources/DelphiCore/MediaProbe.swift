import AVFoundation
import CoreMedia
import Foundation
import UniformTypeIdentifiers

/// Container and per-track inspection for audio-atlas and video-atlas.
/// What AVFoundation cannot reach — bitrate mode, chroma subsampling, GOP
/// structure, encoder library, per-track stream size — is absent, not guessed.
public enum MediaProbe: Sendable {

    public struct Row: Identifiable, Hashable, Sendable {
        public let label: String
        public let value: String
        /// Decibels behind `value`, for a level bar. `-.infinity` is silence.
        public var level: Double?
        public var id: String { label }

        public init(label: String, value: String, level: Double? = nil) {
            (self.label, self.value, self.level) = (label, value, level)
        }
    }

    /// Decibel scale a level bar covers, up to 0.
    public static let levelFloor = -60.0

    /// Share of a level bar, 0...1, for decibels between `levelFloor` and full scale.
    public static func levelShare(_ decibels: Double) -> Double {
        min(1, max(0, 1 - decibels / levelFloor))
    }

    public struct Section: Identifiable, Hashable, Sendable {
        public let title: String
        public let rows: [Row]
        public var id: String { title }

        public init(title: String, rows: [Row]) {
            (self.title, self.rows) = (title, rows)
        }
    }

    public struct Tags: Hashable, Sendable {
        public init() {}

        public var title: String?
        public var artist: String?
        public var album: String?
        public var artwork: Data?

        public var isEmpty: Bool { title == nil && artist == nil && album == nil && artwork == nil }
    }

    public struct Result: Sendable {
        public var sections: [Section]
        public var tags: Tags
        public var duration: Double
    }

    public static func probe(url: URL) async throws -> Result {
        let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
        async let loadedDuration = asset.load(.duration)
        async let loadedMetadata = asset.load(.commonMetadata)
        async let loadedVideo = asset.loadTracks(withMediaType: .video)
        async let loadedAudio = asset.loadTracks(withMediaType: .audio)
        async let loadedSubtitle = asset.loadTracks(withMediaType: .subtitle)
        async let loadedCaptions = asset.loadTracks(withMediaType: .closedCaption)
        let (duration, metadata) = try await (loadedDuration, loadedMetadata)
        let video = try await loadedVideo
        let audio = try await loadedAudio
        let text = try await loadedSubtitle + loadedCaptions

        let seconds = duration.isNumeric ? duration.seconds : 0
        let counts = [
            (video.count, String(localized: "\(video.count) video")),
            (audio.count, String(localized: "\(audio.count) audio")),
            (text.count, String(localized: "\(text.count) text")),
        ].filter { $0.0 > 0 }.map(\.1)

        var sections: [Section] = [
            Section(title: String(localized: "General"), rows: try await generalRows(url: url, counts: counts,
                                                                  duration: seconds, metadata: metadata))
        ]
        for (index, track) in video.enumerated() {
            sections.append(Section(title: String(localized: "Video #\(index + 1)"), rows: try await videoRows(track)))
        }
        for (index, track) in audio.enumerated() {
            sections.append(Section(title: String(localized: "Audio #\(index + 1)"), rows: try await audioRows(track)))
        }
        for (index, track) in text.enumerated() {
            sections.append(Section(title: String(localized: "Text #\(index + 1)"), rows: try await textRows(track)))
        }

        return Result(
            sections: sections.filter { !$0.rows.isEmpty },
            tags: await tags(from: metadata),
            duration: seconds
        )
    }

    public static func report(_ sections: [Section]) -> String {
        sections
            .map { section in
                ([section.title] + section.rows.map { "  \($0.label): \($0.value)" }).joined(separator: "\n")
            }
            .joined(separator: "\n\n")
    }

    // MARK: - Sections

    private static func generalRows(
        url: URL,
        counts: [String],
        duration: Double,
        metadata: [AVMetadataItem]
    ) async throws -> [Row] {
        var rows: [Row] = []
        if let type = UTType(filenameExtension: url.pathExtension)?.localizedDescription {
            rows.append(Row(label: String(localized: "Container"), value: type))
        }

        let bytes = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).flatMap { $0 } ?? 0
        if bytes > 0 {
            rows.append(Row(label: String(localized: "Size"), value: ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)))
        }
        if duration > 0 {
            rows.append(Row(label: String(localized: "Duration"), value: Timecode.clock(seconds: duration)))
            if bytes > 0 {
                rows.append(Row(label: String(localized: "Overall bitrate"), value: bitrate(Double(bytes) * 8 / duration)))
            }
        }

        if !counts.isEmpty {
            rows.append(Row(label: String(localized: "Streams"), value: counts.joined(separator: " · ")))
        }

        if let title = await value(metadata, .commonIdentifierTitle) {
            rows.append(Row(label: String(localized: "Title"), value: title))
        }
        if let software = await value(metadata, .commonIdentifierSoftware) {
            rows.append(Row(label: String(localized: "Encoded with"), value: software))
        }
        if let created = await value(metadata, .commonIdentifierCreationDate) {
            rows.append(Row(label: String(localized: "Encoded"), value: created))
        }
        return rows
    }

    private static func videoRows(_ track: AVAssetTrack) async throws -> [Row] {
        let (formats, size, transform, frameRate, dataRate, timeRange, traits) = try await track.load(
            .formatDescriptions, .naturalSize, .preferredTransform, .nominalFrameRate, .estimatedDataRate, .timeRange, .mediaCharacteristics
        )

        var rows: [Row] = []
        if let format = formats.first {
            rows.append(Row(label: String(localized: "Codec"), value: codecName(format)))
            rows.append(Row(label: String(localized: "Codec ID"), value: fourCC(CMFormatDescriptionGetMediaSubType(format))))
        }

        let rotation = (atan2(Double(transform.b), Double(transform.a)) * 180 / .pi).rounded()
        let rotated = abs(rotation) == 90 || abs(rotation) == 270
        let width = Int((rotated ? size.height : size.width).rounded())
        let height = Int((rotated ? size.width : size.height).rounded())
        if width > 0 && height > 0 {
            rows.append(Row(label: String(localized: "Frame size"),
                            value: "\(width) × \(height) (\(ratio(Double(width) / Double(height))))"))
        }
        if rotation != 0 {
            rows.append(Row(label: String(localized: "Rotation"), value: "\(Int((rotation + 360).truncatingRemainder(dividingBy: 360)))°"))
        }
        if frameRate > 0 {
            rows.append(Row(label: String(localized: "Frame rate"), value: fps(Double(frameRate))))
            let seconds = timeRange.duration.isNumeric ? timeRange.duration.seconds : 0
            if seconds > 0 {
                rows.append(Row(label: String(localized: "Frames"), value: "\(Int((seconds * Double(frameRate)).rounded()))"))
            }
        }
        if dataRate > 0 { rows.append(Row(label: String(localized: "Bitrate"), value: bitrate(Double(dataRate)))) }

        if let format = formats.first {
            let colour = [
                kCMFormatDescriptionExtension_ColorPrimaries,
                kCMFormatDescriptionExtension_TransferFunction,
                kCMFormatDescriptionExtension_YCbCrMatrix,
            ].compactMap { CMFormatDescriptionGetExtension(format, extensionKey: $0) as? String }
            if !colour.isEmpty { rows.append(Row(label: String(localized: "Colour"), value: colour.joined(separator: " · "))) }

            if let depth = CMFormatDescriptionGetExtension(format, extensionKey: kCMFormatDescriptionExtension_Depth) as? Int {
                rows.append(Row(label: String(localized: "Bit depth"), value: "\(depth) bit"))
            }
        }
        if traits.contains(.containsHDRVideo) { rows.append(Row(label: "HDR", value: String(localized: "Yes"))) }

        if timeRange.duration.isNumeric, timeRange.duration.seconds > 0 {
            rows.append(Row(label: String(localized: "Duration"), value: Timecode.clock(seconds: timeRange.duration.seconds)))
        }
        if let language = try await track.load(.languageCode) {
            rows.append(Row(label: String(localized: "Language"), value: language))
        }
        return rows
    }

    private static func audioRows(_ track: AVAssetTrack) async throws -> [Row] {
        let (formats, dataRate, timeRange) = try await track.load(.formatDescriptions, .estimatedDataRate, .timeRange)

        var rows: [Row] = []
        if let format = formats.first {
            rows.append(Row(label: String(localized: "Codec"), value: codecName(format)))
            rows.append(Row(label: String(localized: "Codec ID"), value: fourCC(CMFormatDescriptionGetMediaSubType(format))))

            if let basic = CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee {
                rows.append(Row(label: String(localized: "Channels"), value: "\(basic.mChannelsPerFrame)"))
                if basic.mSampleRate > 0 {
                    rows.append(Row(label: String(localized: "Sample rate"), value: "\(Int(basic.mSampleRate)) Hz"))
                }
                if basic.mBitsPerChannel > 0 {
                    rows.append(Row(label: String(localized: "Bit depth"), value: "\(basic.mBitsPerChannel) bit"))
                }
            }
        }
        if dataRate > 0 { rows.append(Row(label: String(localized: "Bitrate"), value: bitrate(Double(dataRate)))) }
        if timeRange.duration.isNumeric, timeRange.duration.seconds > 0 {
            rows.append(Row(label: String(localized: "Duration"), value: Timecode.clock(seconds: timeRange.duration.seconds)))
        }
        if let language = try await track.load(.languageCode) {
            rows.append(Row(label: String(localized: "Language"), value: language))
        }
        return rows
    }

    private static func textRows(_ track: AVAssetTrack) async throws -> [Row] {
        let (formats, timeRange) = try await track.load(.formatDescriptions, .timeRange)

        var rows: [Row] = []
        if let format = formats.first {
            rows.append(Row(label: String(localized: "Format"), value: codecName(format)))
            rows.append(Row(label: String(localized: "Codec ID"), value: fourCC(CMFormatDescriptionGetMediaSubType(format))))
        }
        if timeRange.duration.isNumeric, timeRange.duration.seconds > 0 {
            rows.append(Row(label: String(localized: "Duration"), value: Timecode.clock(seconds: timeRange.duration.seconds)))
        }
        if let language = try await track.load(.languageCode) {
            rows.append(Row(label: String(localized: "Language"), value: language))
        }
        return rows
    }

    // MARK: - Metadata

    private static func tags(from metadata: [AVMetadataItem]) async -> Tags {
        var tags = Tags()
        tags.title = await value(metadata, .commonIdentifierTitle)
        tags.artist = await value(metadata, .commonIdentifierArtist)
        tags.album = await value(metadata, .commonIdentifierAlbumName)
        if let item = AVMetadataItem.metadataItems(from: metadata, filteredByIdentifier: .commonIdentifierArtwork).first {
            tags.artwork = try? await item.load(.dataValue)
        }
        return tags
    }

    private static func value(_ metadata: [AVMetadataItem], _ identifier: AVMetadataIdentifier) async -> String? {
        guard let item = AVMetadataItem.metadataItems(from: metadata, filteredByIdentifier: identifier).first,
              let text = try? await item.load(.stringValue)
        else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    // MARK: - Formatting

    public static func fourCC(_ code: FourCharCode) -> String {
        let bytes = [UInt8(truncatingIfNeeded: code >> 24), UInt8(truncatingIfNeeded: code >> 16),
                     UInt8(truncatingIfNeeded: code >> 8), UInt8(truncatingIfNeeded: code)]
        return String(decoding: bytes, as: UTF8.self).trimmingCharacters(in: .whitespaces)
    }

    private static let codecNames: [String: String] = [
        "avc1": "AVC / H.264", "hvc1": "HEVC / H.265", "hev1": "HEVC / H.265",
        "av01": "AV01", "vp09": "VP9", "mp4v": "MPEG-4 Visual",
        "apch": "ProRes 422 HQ", "apcn": "ProRes 422", "apcs": "ProRes 422 LT",
        "apco": "ProRes 422 Proxy", "ap4h": "ProRes 4444", "ap4x": "ProRes 4444 XQ",
        "jpeg": "Motion JPEG", "dvh1": "DV", "mp4a": "AAC", "aac ": "AAC",
        "alac": "Apple Lossless", ".mp3": "MP3",
        "lpcm": "Linear PCM", "sowt": "Linear PCM", "twos": "Linear PCM",
        "ulaw": "µ-law", "alaw": "A-law", "ac-3": "AC-3", "ec-3": "E-AC-3",
        "opus": "Opus", "fLaC": "FLAC", "tx3g": "3GPP Timed Text",
        "c608": "CEA-608", "c708": "CEA-708", "wvtt": "WebVTT", "sbtl": "Subtitle",
    ]

    private static func codecName(_ format: CMFormatDescription) -> String {
        let code = fourCC(CMFormatDescriptionGetMediaSubType(format))
        return codecNames[code] ?? code.uppercased()
    }

    public static func bitrate(_ bitsPerSecond: Double) -> String {
        bitsPerSecond >= 1e6
            ? String(format: "%.2f Mb/s", bitsPerSecond / 1e6)
            : "\(Int((bitsPerSecond / 1e3).rounded())) kb/s"
    }

    public static func fps(_ value: Double) -> String {
        var text = String(format: "%.3f", value)
        while text.contains("."), text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return String(localized: "\(text) fps")
    }

    private static let ratios: [(Double, String)] = [
        (16.0 / 9, "16:9"), (4.0 / 3, "4:3"), (9.0 / 16, "9:16"), (1, "1:1"),
        (21.0 / 9, "21:9"), (2.39, "2.39:1"), (2.35, "2.35:1"), (1.85, "1.85:1"),
        (3.0 / 2, "3:2"), (5.0 / 4, "5:4"),
    ]

    public static func ratio(_ value: Double) -> String {
        ratios.first { abs($0.0 - value) < 0.01 }?.1 ?? String(format: "%.2f:1", value)
    }
}


extension MediaProbe {
    /// Peak, RMS and gated loudness of a scan, as a section with level bars.
    public static func loudness(_ scan: AudioDSP.Scan) -> Section {
        func decibels(_ value: Double) -> String {
            value.isFinite ? String(format: "%.1f dBFS", value) : "-\u{221E} dBFS"
        }
        var rows = [
            Row(label: String(localized: "Peak"), value: decibels(scan.peakDb), level: scan.peakDb),
            Row(label: "RMS", value: decibels(scan.rmsDb), level: scan.rmsDb),
        ]
        if let lufs = scan.lufs {
            rows.append(Row(label: String(localized: "Loudness"), value: String(format: "%.1f LUFS", lufs), level: lufs))
        }
        return Section(title: String(localized: "Loudness"), rows: rows)
    }
}

/// Re-encoding and passthrough exports through AVFoundation, and the time and file text the media tools share.
public enum MediaExport: Sendable {
    public enum Failure: Error { case noAudio, noVideo, exportFailed }

    public typealias Progress = AudioRender.Progress

    // CMTime(seconds:) truncates
    public static func time(_ seconds: Double) -> CMTime {
        guard seconds.isFinite else { return .zero }
        return CMTime(value: CMTimeValue((seconds * 60000).rounded()), timescale: 60000)
    }

    public static func baseName(_ url: URL, fallback: String) -> String {
        let base = url.deletingPathExtension().lastPathComponent
        return base.isEmpty ? fallback : base
    }

    /// `HH:MM:SS.mmm`, as the web's `formatTimestamp(ms, '.')`.
    public static func timestamp(_ seconds: Double) -> String {
        let t = Int((max(0, seconds) * 1000).rounded())
        return String(format: "%02d:%02d:%02d.%03d", t / 3_600_000, t / 60_000 % 60, t / 1000 % 60, t % 1000)
    }

    public static func fileDetail(_ url: URL) -> String {
        let bytes = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        let size = ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
        return "\(url.pathExtension) · \(size)"
    }

    public static func audioDetail(_ scan: AudioDSP.Scan) -> String {
        String(format: "%.2f s · %.0f Hz · %d ch", scan.duration, scan.sampleRate, scan.channelCount)
    }

    /// `fallback` is a re-encoding preset, tried when the container or codec refuses `preset`.
    public static func export(_ asset: AVAsset, preset: String, fallback: String? = nil, as fileType: AVFileType,
                              range: CMTimeRange? = nil, to output: URL, progress: @escaping Progress) async throws {
        do {
            try await run(asset, preset: preset, as: fileType, range: range, to: output, progress: progress)
        } catch {
            guard let fallback, fallback != preset, !Task.isCancelled else { throw error }
            try await run(asset, preset: fallback, as: fileType, range: range, to: output, progress: progress)
        }
    }

    private static func run(_ asset: AVAsset, preset: String, as fileType: AVFileType, range: CMTimeRange?,
                            to output: URL, progress: @escaping Progress) async throws {
        guard let session = AVAssetExportSession(asset: asset, presetName: preset) else { throw Failure.exportFailed }
        if let range { session.timeRange = range }
        nonisolated(unsafe) let monitored = session
        let monitor = Task {
            for await state in monitored.states(updateInterval: 0.2) {
                if case .exporting(let exporting) = state { progress(exporting.fractionCompleted) }
            }
        }
        defer { monitor.cancel() }
        try? FileManager.default.removeItem(at: output)
        try await session.export(to: output, as: fileType)
    }

    /// A copy of the asset holding only its `mediaType` tracks.
    public static func composition(of asset: AVAsset, keeping mediaType: AVMediaType, firstOnly: Bool) async throws -> AVMutableComposition {
        let composition = AVMutableComposition()
        var tracks = try await asset.loadTracks(withMediaType: mediaType)
        if firstOnly { tracks = Array(tracks.prefix(1)) }
        for track in tracks {
            guard let copy = composition.addMutableTrack(withMediaType: mediaType, preferredTrackID: kCMPersistentTrackID_Invalid) else {
                throw Failure.exportFailed
            }
            let range = try await track.load(.timeRange)
            try copy.insertTimeRange(range, of: track, at: range.start)
            copy.preferredTransform = try await track.load(.preferredTransform)
        }
        return composition
    }

    /// The first audio track as WAV or M4A; AAC and ALAC go to M4A without re-encoding. `scratch` is a folder for an
    /// intermediate file, needed when the container cannot be read as audio directly.
    public static func extractAudio(from video: URL, format: AudioFormat, to output: URL, scratch: URL,
                                    progress: @escaping Progress) async throws {
        let asset = AVURLAsset(url: video)
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else { throw Failure.noAudio }

        if format == .wav {
            // other containers need m4a
            do {
                return try AudioRender.render(source: video, to: output, format: .wav, progress: progress)
            } catch AudioRender.Failure.tooLongForWav {
                throw AudioRender.Failure.tooLongForWav
            } catch {
                try Task.checkCancellation()
            }
            let intermediate = scratch.appendingPathComponent("intermediate.m4a")
            defer { try? FileManager.default.removeItem(at: intermediate) }
            try await extractAudio(from: video, format: .m4a, to: intermediate, scratch: scratch) { progress($0 / 2) }
            try AudioRender.render(source: intermediate, to: output, format: .wav) { progress(0.5 + $0 / 2) }
            return
        }

        let subtypes = try await track.load(.formatDescriptions).map(\.mediaSubType)
        let passthrough = !subtypes.isEmpty && subtypes.allSatisfy { $0 == .mpeg4AAC || $0 == .appleLossless }
        let audioOnly = try await composition(of: asset, keeping: .audio, firstOnly: true)
        try await export(audioOnly, preset: passthrough ? AVAssetExportPresetPassthrough : AVAssetExportPresetAppleM4A,
                         fallback: AVAssetExportPresetAppleM4A, as: .m4a, to: output, progress: progress)
    }

    #if DEBUG
    public static func selfCheck() {
        assert(timestamp(3661.5) == "01:01:01.500" && timestamp(-1) == "00:00:00.000")
        assert(time(1.5).value == 90000 && time(.nan) == .zero)
        assert(baseName(URL(fileURLWithPath: "/a/b.wav"), fallback: "x") == "b")
        assert(MediaProbe.ratio(16.0 / 9) == "16:9" && MediaProbe.fps(29.97) == "29.97 fps" && MediaProbe.bitrate(128_000) == "128 kb/s")
    }
    #endif
}
