import CoreGraphics
import JavaScriptCore
import SwiftUI

// MARK: - Error

public struct ImageTracerError: Error, LocalizedError {
    public let message: String
    public var errorDescription: String? { message }
}

// MARK: - Presets

public enum TracerPreset: String, CaseIterable, Identifiable, Sendable {
    case `default`
    case posterized1, posterized2, posterized3
    case curvy, sharp, detailed, smoothed
    case grayscale, fixedpalette
    case randomsampling1, randomsampling2
    case artistic1, artistic2, artistic3, artistic4

    public var id: String { rawValue }

    public var displayName: LocalizedStringKey {
        switch self {
        case .default: return "Default"
        case .posterized1: return "Monoposto"
        case .posterized2: return "Saul's World"
        case .posterized3: return "Powders"
        case .curvy: return "Bouba"
        case .sharp: return "Kiki"
        case .detailed: return "Intricate"
        case .smoothed: return "Papered"
        case .grayscale: return "Mono"
        case .fixedpalette: return "Genlock"
        case .randomsampling1: return "Logan"
        case .randomsampling2: return "Clockwise"
        case .artistic1: return "Theories"
        case .artistic2: return "Dustbowl"
        case .artistic3: return "Warrant"
        case .artistic4: return "Sparkle"
        }
    }
}

// MARK: - Engine

@MainActor
public final class ImageTracerEngine {

    private let jsSource: String

    public init?() {
        guard let url = Bundle.module.url(forResource: "imagetracer_v1.2.6", withExtension: "js"),
              let js = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        jsSource = js
    }

    /// Trace a CGImage to SVG. Pixel extraction happens on main thread,
    /// JS tracing runs on a background GCD queue.
    public func trace(
        image: CGImage,
        preset: TracerPreset,
        overrides: [String: Any] = [:]
    ) async -> Result<String, ImageTracerError> {
        // Prepare data on main thread
        let scaled = Self.scaleImage(image, maxDimension: 600)
        let width = scaled.width
        let height = scaled.height

        guard let pixels = Self.extractRGBA(from: scaled) else {
            return .failure(ImageTracerError(message: "Failed to read image pixels"))
        }

        let source = jsSource
        let presetName = preset.rawValue
        let optsJSON: String
        if !overrides.isEmpty,
           let data = try? JSONSerialization.data(withJSONObject: overrides),
           let str = String(data: data, encoding: .utf8) {
            optsJSON = str
        } else {
            optsJSON = "{}"
        }

        // Run JS tracing on background thread
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let result = Self.runTracer(
                    jsSource: source, pixels: pixels,
                    width: width, height: height,
                    preset: presetName, optsJSON: optsJSON
                )
                continuation.resume(returning: result)
            }
        }
    }

    // MARK: - JS Execution (runs on background thread)

    private nonisolated static func runTracer(
        jsSource: String, pixels: [UInt8],
        width: Int, height: Int,
        preset: String, optsJSON: String
    ) -> Result<String, ImageTracerError> {
        guard let ctx = JSContext() else {
            return .failure(ImageTracerError(message: "Failed to create JS context"))
        }
        ctx.exceptionHandler = { _, _ in }
        ctx.evaluateScript("var self = this;")  // shim for UMD: library assigns to self.ImageTracer
        ctx.evaluateScript(jsSource)

        ctx.setObject(pixels, forKeyedSubscript: "pixelArray" as NSString)
        ctx.setObject(width, forKeyedSubscript: "imgWidth" as NSString)
        ctx.setObject(height, forKeyedSubscript: "imgHeight" as NSString)
        ctx.setObject(preset, forKeyedSubscript: "presetName" as NSString)
        ctx.setObject(optsJSON, forKeyedSubscript: "overridesJSON" as NSString)

        let script = """
        (function() {
            try {
                var data = new Uint8ClampedArray(pixelArray);
                var imgd = { data: data, width: imgWidth, height: imgHeight };
                var opts = Object.assign({}, ImageTracer.optionpresets[presetName] || {});
                var overrides = JSON.parse(overridesJSON);
                for (var k in overrides) opts[k] = overrides[k];
                var svg = ImageTracer.imagedataToSVG(imgd, opts);
                return JSON.stringify({ svg: svg });
            } catch(e) {
                return JSON.stringify({ error: e.message || String(e) });
            }
        })()
        """

        guard let result = ctx.evaluateScript(script),
              let jsonString = result.toString(),
              jsonString != "undefined",
              let jsonData = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            return .failure(ImageTracerError(message: "Tracer returned no result"))
        }

        if let error = json["error"] as? String {
            return .failure(ImageTracerError(message: error))
        }

        guard let svg = json["svg"] as? String else {
            return .failure(ImageTracerError(message: "No SVG output"))
        }

        return .success(svg)
    }

    // MARK: - Image Processing

    private static func scaleImage(_ image: CGImage, maxDimension: Int) -> CGImage {
        let maxDim = max(image.width, image.height)
        guard maxDim > maxDimension else { return image }

        let scale = Double(maxDimension) / Double(maxDim)
        let newW = Int(Double(image.width) * scale)
        let newH = Int(Double(image.height) * scale)

        guard let ctx = CGContext(
            data: nil, width: newW, height: newH,
            bitsPerComponent: 8, bytesPerRow: newW * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return image }

        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: newW, height: newH))
        return ctx.makeImage() ?? image
    }

    private static func extractRGBA(from image: CGImage) -> [UInt8]? {
        let w = image.width
        let h = image.height
        var pixels = [UInt8](repeating: 0, count: w * h * 4)

        guard let ctx = CGContext(
            data: &pixels, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: w * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return pixels
    }
}

/// The tracer's options as the tool shows them; `apply` takes a preset's values from imagetracerjs `optionpresets`.
public struct TraceSettings: Equatable, Sendable {
    public var preset = TracerPreset.default
    public var colours = 16
    public var lineThreshold = 1.0
    public var curveThreshold = 1.0
    public var pathOmit = 8.0
    public var strokeWidth = 1.0
    public var scale = 1.0
    public var blurRadius = 0.0
    public var blurDelta = 20.0
    public var colourSampling = 2
    public var minColourRatio = 0.0
    public var roundCoords = 1.0

    public init(preset: TracerPreset = .default, scale: Double = 1) {
        (self.preset, self.scale) = (preset, scale)
    }

    public static let strokes = [0, 0.5, 1, 2, 3, 5]
    public static let scales = [0.5, 1, 2, 3, 5]
    /// imagetracer's zero is 0.01
    public static let leastThreshold = 0.01

    public static let presets: [(preset: TracerPreset, name: String)] = [
        (.default, String(localized: "Default")), (.posterized1, "Monoposto"), (.posterized2, "Saul's World"), (.posterized3, "Powders"),
        (.curvy, "Bouba"), (.sharp, "Kiki"), (.detailed, "Intricate"), (.smoothed, "Papered"),
        (.grayscale, "Mono"), (.fixedpalette, "Genlock"), (.randomsampling1, "Logan"), (.randomsampling2, "Clockwise"),
        (.artistic1, "Theories"), (.artistic2, "Dustbowl"), (.artistic3, "Warrant"), (.artistic4, "Sparkle"),
    ]

    public static func number(_ value: Double) -> String {
        value.rounded() == value ? "\(Int(value))" : String(format: "%g", value)
    }

    public static func strokeLabel(_ width: Double) -> String {
        width == 0 ? String(localized: "None") : number(width)
    }

    public static func smoothing(_ value: Double) -> String {
        value < 0.05 ? "0.01" : String(format: "%.1f", value)
    }

    public mutating func apply(_ chosen: TracerPreset) {
        self = TraceSettings(preset: chosen, scale: scale)
        switch chosen {
        case .default: break
        case .posterized1: (colourSampling, colours) = (0, 2)
        case .posterized2: (colours, blurRadius) = (4, 5)
        case .posterized3: (pathOmit, colourSampling, colours, blurRadius, strokeWidth) = (20, 0, 3, 3, 0)
        case .curvy: lineThreshold = Self.leastThreshold
        case .sharp: curveThreshold = Self.leastThreshold
        case .detailed: (pathOmit, roundCoords, lineThreshold, curveThreshold, colours) = (0, 2, 0.5, 0.5, 64)
        case .smoothed: (blurRadius, blurDelta) = (5, 64)
        case .grayscale: (colourSampling, colours) = (0, 7)
        case .fixedpalette: (colourSampling, colours) = (0, 27)
        case .randomsampling1: (colourSampling, colours) = (1, 8)
        case .randomsampling2: (colourSampling, colours) = (1, 64)
        case .artistic1:
            (colourSampling, pathOmit, blurRadius, blurDelta, lineThreshold, strokeWidth) = (0, 0, 5, 64, Self.leastThreshold, 2)
        case .artistic2: (curveThreshold, colourSampling, colours, strokeWidth) = (Self.leastThreshold, 0, 4, 0)
        case .artistic3: (curveThreshold, lineThreshold, colours) = (10, 10, 8)
        case .artistic4: (curveThreshold, lineThreshold, colours, blurRadius, blurDelta, strokeWidth) = (10, 10, 64, 5, 256, 2)
        }
    }

    public var overrides: [String: Any] {
        [
            "numberofcolors": colours,
            "ltres": max(lineThreshold, Self.leastThreshold),
            "qtres": max(curveThreshold, Self.leastThreshold),
            "pathomit": Int(pathOmit),
            "strokewidth": strokeWidth,
            "scale": scale,
            "blurradius": Int(blurRadius),
            "blurdelta": Int(blurDelta),
            "colorsampling": colourSampling,
            "mincolorratio": minColourRatio,
            "roundcoords": Int(roundCoords),
        ]
    }

    #if DEBUG
    public static func selfCheck() {
        var settings = TraceSettings(scale: 2)
        settings.apply(.sharp)
        assert(settings.scale == 2 && settings.curveThreshold == leastThreshold && settings.preset == .sharp)
        settings.lineThreshold = 0
        assert(settings.overrides["ltres"] as? Double == leastThreshold)
        assert(presets.count == TracerPreset.allCases.count && number(0.5) == "0.5" && number(3) == "3")
    }
    #endif
}
