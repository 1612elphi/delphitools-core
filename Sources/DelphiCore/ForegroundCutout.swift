import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import CoreVideo
import Foundation
import Vision

/// Vision's foreground instances for one image: which subject lies under a point, and the image with only the kept subjects.
public final class ForegroundCutout: @unchecked Sendable {
    public enum Failure: Error {
        case unreadable, noSubject
    }

    public let source: CGImage
    // vision counts from 1
    public let instances: IndexSet
    private let handler: VNImageRequestHandler?
    private let observation: VNInstanceMaskObservation?
    // 0 is background
    private let labels: [UInt8]
    private let labelWidth: Int
    private let labelHeight: Int
    private static let context = CIContext()

    /// Vision's foreground instances of `source`; throws `Failure.noSubject` when it finds none.
    public init(source: CGImage) throws {
        let handler = VNImageRequestHandler(cgImage: source)
        let request = VNGenerateForegroundInstanceMaskRequest()
        try handler.perform([request])
        guard let observation = request.results?.first, !observation.allInstances.isEmpty else { throw Failure.noSubject }
        let buffer = observation.instanceMask
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        let (width, height, stride) = (CVPixelBufferGetWidth(buffer), CVPixelBufferGetHeight(buffer), CVPixelBufferGetBytesPerRow(buffer))
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { throw Failure.noSubject }
        let bytes = base.assumingMemoryBound(to: UInt8.self)
        labels = (0..<height).flatMap { row in (0..<width).map { bytes[row * stride + $0] } }
        (labelWidth, labelHeight) = (width, height)
        (self.source, self.handler, self.observation, instances) = (source, handler, observation, observation.allInstances)
    }

    /// Instances read from a label image instead of Vision, where Vision cannot run (the simulator): a grey level per
    /// pixel, 0 the background, any other level one instance.
    public init(source: CGImage, labels image: CGImage) throws {
        let (width, height) = (image.width, image.height)
        var grey = [UInt8](repeating: 0, count: width * height)
        guard let context = CGContext(data: &grey, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
                                      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { throw Failure.unreadable }
        context.interpolationQuality = .none
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        labels = grey
        (labelWidth, labelHeight) = (width, height)
        instances = IndexSet(grey.lazy.filter { $0 > 0 }.map(Int.init))
        guard !instances.isEmpty else { throw Failure.noSubject }
        (self.source, handler, observation) = (source, nil, nil)
    }

    /// The instance under `share`, a point in shares of the image from the top left; nil for the background.
    public func instance(at share: CGPoint) -> Int? {
        guard (0...1).contains(share.x), (0...1).contains(share.y) else { return nil }
        let x = min(labelWidth - 1, Int(share.x * CGFloat(labelWidth)))
        let y = min(labelHeight - 1, Int(share.y * CGFloat(labelHeight)))
        let label = Int(labels[y * labelWidth + x])
        return label == 0 ? nil : label
    }

    /// Share of the image the `kept` instances cover.
    public func share(of kept: IndexSet) -> Double {
        guard !labels.isEmpty else { return 0 }
        return Double(labels.lazy.filter { kept.contains(Int($0)) }.count) / Double(labels.count)
    }

    /// `source` with only the `kept` instances, the rest transparent, or `fill` when it is set.
    public func render(keeping kept: IndexSet, fill: CGColor?) throws -> CGImage? {
        let original = CIImage(cgImage: source)
        let blend = CIFilter.blendWithMask()
        blend.inputImage = original
        blend.maskImage = try mask(keeping: kept)
        blend.backgroundImage = fill.map { CIImage(color: CIColor(cgColor: $0)).cropped(to: original.extent) } ?? CIImage.empty()
        guard let output = blend.outputImage else { return nil }
        return Self.context.createCGImage(output, from: original.extent)
    }

    private func mask(keeping kept: IndexSet) throws -> CIImage {
        let extent = CGRect(x: 0, y: 0, width: source.width, height: source.height)
        guard !kept.isEmpty else { return CIImage(color: .black).cropped(to: extent) }
        if let observation, let handler {
            return CIImage(cvPixelBuffer: try observation.generateScaledMaskForImage(forInstances: kept, from: handler))
        }
        let bytes = labels.map { kept.contains(Int($0)) ? UInt8(255) : 0 }
        let small = CIImage(bitmapData: Data(bytes), bytesPerRow: labelWidth, size: CGSize(width: labelWidth, height: labelHeight),
                            format: .L8, colorSpace: nil)
        return small.transformed(by: CGAffineTransform(scaleX: extent.width / CGFloat(labelWidth), y: extent.height / CGFloat(labelHeight)))
            .cropped(to: extent)
    }
}
