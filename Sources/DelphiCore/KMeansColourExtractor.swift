import CoreGraphics

// MARK: - KMeansColourExtractor

/// Extracts dominant colours from a CGImage using k-means++ clustering.
/// All methods are stateless — no stored properties, no shared mutable state.
public enum KMeansColourExtractor {

    // MARK: - Pixel

    private typealias Pixel = (r: Double, g: Double, b: Double)

    // MARK: - Public API

    /// Extract dominant colours from a full image.
    /// - Parameters:
    ///   - image: Source image in any pixel format.
    ///   - count: Number of clusters (palette size).
    ///   - maxIterations: Upper bound on k-means iterations.
    /// - Returns: Up to `count` colours sorted by cluster size (most dominant first).
    public static func extract(
        from image: CGImage,
        count: Int = 6,
        maxIterations: Int = 20
    ) -> [DelphiColour] {
        let pixels = downsamplePixels(from: image)
        return kmeans(pixels: pixels, count: count, maxIterations: maxIterations)
    }

    /// Extract dominant colours from a normalised sub-rect of an image.
    /// - Parameters:
    ///   - image: Source image.
    ///   - rect: Region of interest in normalised (0–1) coordinates.
    ///   - count: Number of clusters.
    ///   - maxIterations: Upper bound on k-means iterations.
    /// - Returns: Up to `count` colours sorted by cluster size (most dominant first).
    public static func extract(
        from image: CGImage,
        rect: CGRect,
        count: Int = 6,
        maxIterations: Int = 20
    ) -> [DelphiColour] {
        guard let cropped = crop(image: image, normalisedRect: rect) else {
            return extract(from: image, count: count, maxIterations: maxIterations)
        }
        let pixels = downsamplePixels(from: cropped)
        return kmeans(pixels: pixels, count: count, maxIterations: maxIterations)
    }

    // MARK: - Crop

    private static func crop(image: CGImage, normalisedRect rect: CGRect) -> CGImage? {
        let w = Double(image.width)
        let h = Double(image.height)
        let pixelRect = CGRect(
            x: rect.minX * w,
            y: rect.minY * h,
            width: rect.width * w,
            height: rect.height * h
        )
        return image.cropping(to: pixelRect)
    }

    // MARK: - Downsample

    /// Renders `image` into a ~100×100 RGBA8 bitmap and returns the pixel array.
    private static func downsamplePixels(from image: CGImage) -> [Pixel] {
        let targetSize = 100
        let srcW = image.width
        let srcH = image.height

        // Keep aspect ratio within 100×100 box.
        let scale = Double(targetSize) / Double(max(srcW, srcH))
        let dstW = max(1, Int(Double(srcW) * scale))
        let dstH = max(1, Int(Double(srcH) * scale))

        let bytesPerPixel = 4
        let bytesPerRow = dstW * bytesPerPixel
        var rawBytes = [UInt8](repeating: 0, count: dstH * bytesPerRow)

        guard let context = CGContext(
            data: &rawBytes,
            width: dstW,
            height: dstH,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return [] }

        context.draw(image, in: CGRect(x: 0, y: 0, width: dstW, height: dstH))

        var pixels: [Pixel] = []
        pixels.reserveCapacity(dstW * dstH)

        var i = 0
        while i < rawBytes.count {
            let a = Double(rawBytes[i + 3]) / 255.0
            // Skip near-transparent pixels — they contribute noise.
            if a > 0.1 {
                let r = Double(rawBytes[i])     / 255.0
                let g = Double(rawBytes[i + 1]) / 255.0
                let b = Double(rawBytes[i + 2]) / 255.0
                // Un-premultiply alpha.
                if a > 0 {
                    pixels.append((r: r / a, g: g / a, b: b / a))
                } else {
                    pixels.append((r: r, g: g, b: b))
                }
            }
            i += bytesPerPixel
        }

        return pixels
    }

    // MARK: - K-Means Core

    private static func kmeans(
        pixels: [Pixel],
        count: Int,
        maxIterations: Int
    ) -> [DelphiColour] {
        guard !pixels.isEmpty, count > 0 else { return [] }

        let k = min(count, pixels.count)
        var centroids = initializeCentroids(pixels: pixels, k: k)
        var assignments = [Int](repeating: 0, count: pixels.count)

        for _ in 0 ..< maxIterations {
            // Assignment step.
            var changed = false
            for idx in 0 ..< pixels.count {
                let nearest = nearestCentroid(pixel: pixels[idx], centroids: centroids)
                if assignments[idx] != nearest {
                    assignments[idx] = nearest
                    changed = true
                }
            }
            if !changed { break }

            // Update step — recompute centroid as mean of assigned pixels.
            var sums = [(r: Double, g: Double, b: Double, n: Int)](
                repeating: (0, 0, 0, 0),
                count: k
            )
            for idx in 0 ..< pixels.count {
                let c = assignments[idx]
                sums[c].r += pixels[idx].r
                sums[c].g += pixels[idx].g
                sums[c].b += pixels[idx].b
                sums[c].n += 1
            }
            for c in 0 ..< k {
                let n = Double(sums[c].n)
                if n > 0 {
                    centroids[c] = (r: sums[c].r / n, g: sums[c].g / n, b: sums[c].b / n)
                }
            }
        }

        // Count cluster sizes for sorting.
        var sizes = [Int](repeating: 0, count: k)
        for a in assignments { sizes[a] += 1 }

        // Build (centroid, size) pairs, filter empty clusters, sort by size descending.
        let result = (0 ..< k)
            .filter { sizes[$0] > 0 }
            .sorted { sizes[$0] > sizes[$1] }
            .map { c -> DelphiColour in
                let p = centroids[c]
                return DelphiColour(
                    r: max(0, min(1, p.r)),
                    g: max(0, min(1, p.g)),
                    b: max(0, min(1, p.b))
                )
            }

        return result
    }

    // MARK: - K-Means++ Initialisation

    /// Selects initial centroids using the k-means++ weighted distance strategy.
    private static func initializeCentroids(pixels: [Pixel], k: Int) -> [Pixel] {
        var centroids: [Pixel] = []
        centroids.reserveCapacity(k)

        // Pick first centroid uniformly at random.
        let firstIndex = Int.random(in: 0 ..< pixels.count)
        centroids.append(pixels[firstIndex])

        // Pick remaining centroids weighted by squared distance to nearest centroid.
        while centroids.count < k {
            var distances = [Double](repeating: 0, count: pixels.count)
            var totalDistance = 0.0
            for i in 0 ..< pixels.count {
                let d = minSquaredDistance(pixel: pixels[i], centroids: centroids)
                distances[i] = d
                totalDistance += d
            }

            guard totalDistance > 0 else {
                // All pixels are identical — pad with the same centroid.
                while centroids.count < k { centroids.append(centroids[0]) }
                break
            }

            // Weighted random selection.
            var threshold = Double.random(in: 0 ..< totalDistance)
            var chosen = pixels.count - 1
            for i in 0 ..< pixels.count {
                threshold -= distances[i]
                if threshold <= 0 {
                    chosen = i
                    break
                }
            }
            centroids.append(pixels[chosen])
        }

        return centroids
    }

    // MARK: - Distance Helpers

    /// Index of the nearest centroid to `pixel`.
    private static func nearestCentroid(pixel: Pixel, centroids: [Pixel]) -> Int {
        var bestIndex = 0
        var bestDist = Double.infinity
        for i in 0 ..< centroids.count {
            let d = distanceSquared(pixel, centroids[i])
            if d < bestDist {
                bestDist = d
                bestIndex = i
            }
        }
        return bestIndex
    }

    /// Minimum squared distance from `pixel` to any centroid in `centroids`.
    private static func minSquaredDistance(pixel: Pixel, centroids: [Pixel]) -> Double {
        var best = Double.infinity
        for c in centroids {
            let d = distanceSquared(pixel, c)
            if d < best { best = d }
        }
        return best
    }

    /// Squared Euclidean distance in RGB space.
    private static func distanceSquared(_ a: Pixel, _ b: Pixel) -> Double {
        let dr = a.r - b.r
        let dg = a.g - b.g
        let db = a.b - b.b
        return dr * dr + dg * dg + db * db
    }
}
