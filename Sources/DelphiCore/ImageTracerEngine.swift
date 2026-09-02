import CoreGraphics
import JavaScriptCore
import SwiftUI

// MARK: - Error

public struct ImageTracerError: Error, LocalizedError {
    public let message: String
    public var errorDescription: String? { message }
}

// MARK: - Presets

public enum TracerPreset: String, CaseIterable, Identifiable {
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
