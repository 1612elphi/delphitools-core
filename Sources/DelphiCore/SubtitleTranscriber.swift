import AVFoundation
import Foundation
import Speech

/// On-device transcription through the system speech models already installed. Never requests a model download.
@available(macOS 26.0, iOS 26.0, *)
public enum SubtitleTranscriber: Sendable {
    public enum Failure: Error, Sendable {
        case unreadable, unavailable, failed
    }

    private static func tag(_ locale: Locale) -> String { locale.identifier(.bcp47) }

    /// Locale.current without the "-u-" preference extensions, which never match a model's locale.
    public static var deviceLocale: Locale {
        let current = Locale.current
        let parts = [current.language.languageCode?.identifier, current.region?.identifier].compactMap { $0 }
        return parts.isEmpty ? current : Locale(identifier: parts.joined(separator: "-"))
    }

    /// Installed model locales, the most spoken languages first.
    public static func locales() async -> [Locale] {
        guard SpeechTranscriber.isAvailable else { return [] }
        let names = Locale.current
        return mostSpokenFirst(await SpeechTranscriber.installedLocales, code: { $0.language.languageCode?.identifier }) {
            names.localizedString(forIdentifier: $0.identifier) ?? $0.identifier
        }
    }

    // ethnologue 2026, total speakers
    static let mostSpoken = ["en", "zh", "hi", "es", "ar", "fr", "bn", "pt", "id", "ur"]

    /// Languages in `mostSpoken` first, in its order, each language's variants by name; the rest by name.
    public static func mostSpokenFirst<Item>(_ items: [Item], code: (Item) -> String?, name: (Item) -> String) -> [Item] {
        func rank(_ item: Item) -> Int { code(item).flatMap { mostSpoken.firstIndex(of: $0) } ?? mostSpoken.count }
        return items.sorted { a, b in
            let (ra, rb) = (rank(a), rank(b))
            return ra != rb ? ra < rb : name(a).localizedCaseInsensitiveCompare(name(b)) == .orderedAscending
        }
    }

    @concurrent
    public static func transcribe(_ url: URL, locale: Locale, progress: @escaping @Sendable (Double) -> Void) async throws -> [SubtitleCue] {
        guard SpeechTranscriber.isAvailable,
              await SpeechTranscriber.installedLocales.contains(where: { tag($0) == tag(locale) }) else { throw Failure.unavailable }
        let (audio, isTemporary) = try await audioFile(from: url)
        defer { if isTemporary { try? FileManager.default.removeItem(at: audio) } }
        do {
            let words = try await analyse(audio, locale: locale, progress: progress)
            try Task.checkCancellation()
            return SubtitleCodec.cues(from: words)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw Failure.failed
        }
    }

    // video reduced to m4a
    private static func audioFile(from url: URL) async throws -> (URL, isTemporary: Bool) {
        let asset = AVURLAsset(url: url)
        guard let tracks = try? await asset.loadTracks(withMediaType: .audio), !tracks.isEmpty else { throw Failure.unreadable }
        let hasVideo = ((try? await asset.loadTracks(withMediaType: .video)) ?? []).isEmpty == false
        guard hasVideo else { return (url, false) }
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else { throw Failure.unreadable }
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).m4a")
        do {
            try await session.export(to: output, as: .m4a)
        } catch is CancellationError {
            try? FileManager.default.removeItem(at: output)
            throw CancellationError()
        } catch {
            try? FileManager.default.removeItem(at: output)
            throw Failure.unreadable
        }
        return (output, true)
    }

    private static func analyse(_ url: URL, locale: Locale, progress: @Sendable (Double) -> Void) async throws -> [SubtitleWord] {
        let file = try AVAudioFile(forReading: url)
        let duration = Double(file.length) / file.processingFormat.sampleRate
        let transcriber = SpeechTranscriber(locale: locale, transcriptionOptions: [], reportingOptions: [], attributeOptions: [.audioTimeRange])
        let analyser = try await SpeechAnalyzer(inputAudioFile: file, modules: [transcriber], finishAfterFile: true)
        return try await withTaskCancellationHandler {
            var words: [SubtitleWord] = []
            for try await result in transcriber.results {
                for run in result.text.runs {
                    guard let range = run.audioTimeRange else { continue }
                    let text = String(result.text[run.range].characters).trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !text.isEmpty else { continue }
                    words.append(SubtitleWord(text: text, start: range.start.seconds, end: range.end.seconds))
                }
                if duration > 0 { progress(min(1, result.range.end.seconds / duration)) }
            }
            return words
        } onCancel: {
            Task { await analyser.cancelAndFinishNow() }
        }
    }

    #if DEBUG
    public static func selfCheck() {
        let codes = ["de", "ur", "af", "en", "zh", "pt"]
        assert(mostSpokenFirst(codes, code: { $0 }, name: { $0 }) == ["en", "zh", "pt", "ur", "af", "de"])
        let variants = ["en-US", "fr-FR", "en-AU", "nl-NL"]
        assert(mostSpokenFirst(variants, code: { String($0.prefix(2)) }, name: { $0 }) == ["en-AU", "en-US", "fr-FR", "nl-NL"])
    }
    #endif
}
