import CoreGraphics
import Foundation

// MARK: - Image Stitcher engine
//
// Port of the web tool's mosaic-tree aspect algebra (components/tools/
// image-stitcher.tsx). The composite is a tree: leaves are images, splits are
// rows (side by side) or columns (stacked). Every node reduces to an aspect
// ratio — a row sums child aspects, a column sums the inverses — and the base
// image pins the composite to its native pixel size. The same layout drives
// the SwiftUI preview and the export render.

/// An imported image, upright.
public struct StitchSource: Identifiable, Sendable {
    public let id = UUID()
    public let image: CGImage
    public let pixelSize: CGSize
    /// Smaller copy for the screen; nil shows `image`.
    public let preview: CGImage?
    /// File name without extension.
    public let name: String

    public init(image: CGImage, preview: CGImage? = nil, name: String = "image") {
        self.image = image
        self.pixelSize = CGSize(width: image.width, height: image.height)
        self.preview = preview
        self.name = name
    }
}

public enum StitchFit: String, CaseIterable, Identifiable, Sendable {
    /// centre-cropped to the base image's aspect
    case match
    /// the image's own aspect
    case cheese
    /// match's cell, letterboxed on a white surround — no crop
    case matte

    public var id: String { rawValue }
}

public enum StitchSide: CaseIterable, Sendable {
    case top, left, right, bottom
}

public enum StitchDir: Sendable {
    case row, col
}

// MARK: - The mosaic tree

public indirect enum StitchNode: Sendable {
    case leaf(key: UUID, srcID: UUID, fit: StitchFit)
    case split(key: UUID, dir: StitchDir, children: [StitchNode])

    public static func leaf(srcID: UUID, fit: StitchFit = .cheese) -> StitchNode {
        .leaf(key: UUID(), srcID: srcID, fit: fit)
    }

    public var key: UUID {
        switch self {
        case .leaf(let key, _, _), .split(let key, _, _): return key
        }
    }

    public var leafSrcIDs: [UUID] {
        switch self {
        case .leaf(_, let srcID, _): return [srcID]
        case .split(_, _, let children): return children.flatMap(\.leafSrcIDs)
        }
    }

    /// The key of the leaf showing source `srcID`.
    public func leafKey(ofSource srcID: UUID) -> UUID? {
        switch self {
        case .leaf(let key, let id, _): id == srcID ? key : nil
        case .split(_, _, let children): children.lazy.compactMap { $0.leafKey(ofSource: srcID) }.first
        }
    }

    /// The source and fit of leaf `key`.
    public func findLeaf(_ key: UUID) -> (srcID: UUID, fit: StitchFit)? {
        switch self {
        case .leaf(let k, let srcID, let fit):
            return k == key ? (srcID, fit) : nil
        case .split(_, _, let children):
            for child in children {
                if let found = child.findLeaf(key) { return found }
            }
            return nil
        }
    }

    /// The tree with leaf `key` set to `fit`.
    public func settingFit(_ fit: StitchFit, forLeaf key: UUID) -> StitchNode {
        switch self {
        case .leaf(let k, let srcID, _) where k == key:
            return .leaf(key: k, srcID: srcID, fit: fit)
        case .leaf:
            return self
        case .split(let k, let dir, let children):
            return .split(key: k, dir: dir, children: children.map { $0.settingFit(fit, forLeaf: key) })
        }
    }

    /// Wrap the node with `key` (nil = the whole composite) in a new split
    /// holding the added leaves on the given side. Geometry-wise wrapping
    /// flattens — a row inside a row lays out identically to one long row —
    /// so the tree can stay naive.
    public func wrapping(key: UUID?, side: StitchSide, adding added: [StitchNode]) -> StitchNode {
        func wrap(_ node: StitchNode) -> StitchNode {
            let dir: StitchDir = (side == .left || side == .right) ? .row : .col
            let children = (side == .left || side == .top) ? added + [node] : [node] + added
            return .split(key: UUID(), dir: dir, children: children)
        }
        guard let key else { return wrap(self) }
        func walk(_ node: StitchNode) -> StitchNode {
            if node.key == key { return wrap(node) }
            if case .split(let k, let dir, let children) = node {
                return .split(key: k, dir: dir, children: children.map(walk))
            }
            return node
        }
        return walk(self)
    }

    /// Splice leaves into a split's child list (seam insert).
    public func inserting(_ added: [StitchNode], intoSplit splitKey: UUID, at index: Int) -> StitchNode {
        guard case .split(let key, let dir, let children) = self else { return self }
        if key == splitKey {
            var spliced = children
            spliced.insert(contentsOf: added, at: min(index, spliced.count))
            return .split(key: key, dir: dir, children: spliced)
        }
        return .split(key: key, dir: dir,
                      children: children.map { $0.inserting(added, intoSplit: splitKey, at: index) })
    }

    /// Two leaves trade contents (image + fit); the mosaic structure itself
    /// never changes — slots stay, pictures move.
    public func swappingContent(_ aKey: UUID, _ bKey: UUID) -> StitchNode {
        guard let a = findLeaf(aKey), let b = findLeaf(bKey) else { return self }
        func walk(_ node: StitchNode) -> StitchNode {
            switch node {
            case .leaf(let k, _, _) where k == aKey:
                return .leaf(key: k, srcID: b.srcID, fit: b.fit)
            case .leaf(let k, _, _) where k == bKey:
                return .leaf(key: k, srcID: a.srcID, fit: a.fit)
            case .leaf:
                return node
            case .split(let k, let dir, let children):
                return .split(key: k, dir: dir, children: children.map(walk))
            }
        }
        return walk(self)
    }

    /// Detach a leaf from its slot (collapsing as needed) and re-wrap the
    /// target so the moved image lands on that side of it.
    public func movingLeaf(_ movedKey: UUID, toSide side: StitchSide, of targetKey: UUID) -> StitchNode {
        guard movedKey != targetKey,
              let moved = findLeaf(movedKey),
              let without = removingLeaf(movedKey)
        else { return self }
        let movedLeaf = StitchNode.leaf(key: movedKey, srcID: moved.srcID, fit: moved.fit)
        return without.wrapping(key: targetKey, side: side, adding: [movedLeaf])
    }

    /// Remove a leaf; single-child splits collapse away. Returns nil when empty.
    public func removingLeaf(_ key: UUID) -> StitchNode? {
        switch self {
        case .leaf(let k, _, _):
            return k == key ? nil : self
        case .split(let k, let dir, let children):
            let kept = children.compactMap { $0.removingLeaf(key) }
            if kept.isEmpty { return nil }
            if kept.count == 1 { return kept[0] }
            return .split(key: k, dir: dir, children: kept)
        }
    }
}

// MARK: - Layout

public struct StitchOp: Identifiable, Sendable {
    public let src: StitchSource
    public let leafKey: UUID
    public let isBase: Bool
    public let fit: StitchFit
    /// source crop in image pixels (centre-crop for match; full bounds otherwise)
    public let source: CGRect
    /// placement in composite pixels
    public let dest: CGRect

    public var id: UUID { leafKey }
}

/// A boundary between two siblings of a split — the "insert here" target.
public struct StitchSeam: Identifiable, Sendable {
    public let splitKey: UUID
    public let at: Int
    public let origin: CGPoint
    public let length: CGFloat
    public let vertical: Bool

    public var id: String { "\(splitKey)-\(at)" }
}

public struct StitchLayout: Sendable {
    public let size: CGSize
    public let ops: [StitchOp]
    public let seams: [StitchSeam]
}

public enum StitchLayoutEngine {

    // ponytail: 16384 = safe render side cap; larger stitches downscale to fit
    public static let maxExportSide: CGFloat = 16384

    /// centre-crop source rect covering a target aspect (w/h)
    public static func coverCrop(_ src: StitchSource, aspect: CGFloat) -> CGRect {
        let w = src.pixelSize.width
        let h = src.pixelSize.height
        if w / h > aspect {
            let sw = h * aspect
            return CGRect(x: (w - sw) / 2, y: 0, width: sw, height: h)
        }
        let sh = w / aspect
        return CGRect(x: 0, y: (h - sh) / 2, width: w, height: sh)
    }

    /// Width over height of `node`; a match or matte leaf takes `baseAspect`.
    public static func aspect(of node: StitchNode, sources: [UUID: StitchSource], baseAspect: CGFloat) -> CGFloat {
        switch node {
        case .leaf(_, let srcID, let fit):
            guard let src = sources[srcID] else { return 1 }
            return fit == .cheese ? src.pixelSize.width / src.pixelSize.height : baseAspect
        case .split(_, let dir, let children):
            let aspects = children.map { aspect(of: $0, sources: sources, baseAspect: baseAspect) }
            return dir == .row
                ? aspects.reduce(0, +)
                : 1 / aspects.reduce(0) { $0 + 1 / $1 }
        }
    }

    /// Every leaf's crop and placement and every seam, scaled so the base image sits at its own pixel size; nil without the base.
    public static func layout(root: StitchNode, sources: [UUID: StitchSource], baseID: UUID) -> StitchLayout? {
        guard let base = sources[baseID] else { return nil }
        let baseAspect = base.pixelSize.width / base.pixelSize.height
        var ops: [StitchOp] = []
        var seams: [StitchSeam] = []

        func walk(_ node: StitchNode, _ rect: CGRect) {
            switch node {
            case .leaf(let key, let srcID, let fit):
                guard let src = sources[srcID] else { return }
                let crop = fit == .match
                    ? coverCrop(src, aspect: rect.width / rect.height)
                    : CGRect(origin: .zero, size: src.pixelSize)
                ops.append(StitchOp(src: src, leafKey: key, isBase: srcID == baseID,
                                    fit: fit, source: crop, dest: rect))
            case .split(let key, let dir, let children):
                let aspects = children.map { aspect(of: $0, sources: sources, baseAspect: baseAspect) }
                if dir == .row {
                    let total = aspects.reduce(0, +)
                    var x = rect.minX
                    for (i, child) in children.enumerated() {
                        let w = rect.width * aspects[i] / total
                        if i > 0 {
                            seams.append(StitchSeam(splitKey: key, at: i,
                                                    origin: CGPoint(x: x, y: rect.minY),
                                                    length: rect.height, vertical: true))
                        }
                        walk(child, CGRect(x: x, y: rect.minY, width: w, height: rect.height))
                        x += w
                    }
                } else {
                    let inverses = aspects.map { 1 / $0 }
                    let total = inverses.reduce(0, +)
                    var y = rect.minY
                    for (i, child) in children.enumerated() {
                        let h = rect.height * inverses[i] / total
                        if i > 0 {
                            seams.append(StitchSeam(splitKey: key, at: i,
                                                    origin: CGPoint(x: rect.minX, y: y),
                                                    length: rect.width, vertical: false))
                        }
                        walk(child, CGRect(x: rect.minX, y: y, width: rect.width, height: h))
                        y += h
                    }
                }
            }
        }

        let rootAspect = aspect(of: root, sources: sources, baseAspect: baseAspect)
        walk(root, CGRect(x: 0, y: 0, width: rootAspect * 1000, height: 1000))

        // normalise so the base image sits at its native pixel size
        let baseOp = ops.first { $0.isBase }
        let k = baseOp.map { base.pixelSize.width / $0.dest.width } ?? 1
        let scale = CGAffineTransform(scaleX: k, y: k)
        return StitchLayout(
            size: CGSize(width: rootAspect * 1000 * k, height: 1000 * k),
            ops: ops.map {
                StitchOp(src: $0.src, leafKey: $0.leafKey, isBase: $0.isBase,
                         fit: $0.fit, source: $0.source, dest: $0.dest.applying(scale))
            },
            seams: seams.map {
                StitchSeam(splitKey: $0.splitKey, at: $0.at,
                           origin: $0.origin.applying(scale),
                           length: $0.length * k, vertical: $0.vertical)
            }
        )
    }

    /// Near-square grid, every cell centre-cropped to the first image's aspect
    /// (batch is match-only — cheese cells would break the grid).
    /// ponytail: cell size = the first image's pixel size; a giant first image
    /// makes a giant grid — add a cell-size control if anyone hits it.
    public static func batchLayout(_ srcs: [StitchSource]) -> StitchLayout? {
        guard let first = srcs.first else { return nil }
        let cellW = first.pixelSize.width
        let cellH = first.pixelSize.height
        let aspect = cellW / cellH
        let cols = Int(ceil(Double(srcs.count).squareRoot()))
        let rows = Int(ceil(Double(srcs.count) / Double(cols)))
        let ops = srcs.enumerated().map { i, src in
            StitchOp(src: src, leafKey: src.id, isBase: i == 0, fit: .match,
                     source: coverCrop(src, aspect: aspect),
                     dest: CGRect(x: CGFloat(i % cols) * cellW, y: CGFloat(i / cols) * cellH,
                                  width: cellW, height: cellH))
        }
        return StitchLayout(size: CGSize(width: CGFloat(cols) * cellW, height: CGFloat(rows) * cellH),
                            ops: ops, seams: [])
    }

    /// The pixel size a layout renders at, downscaled past `maxExportSide`.
    public static func exportSize(_ size: CGSize) -> CGSize {
        let scale = min(1, maxExportSide / max(size.width, size.height, 1))
        return CGSize(width: max(1, (size.width * scale).rounded()), height: max(1, (size.height * scale).rounded()))
    }

    /// Render a layout to a bitmap at `exportSize`, in the base image's colour space. `opaque` mattes the whole
    /// canvas white first — alpha-less formats (JPEG) would otherwise flatten transparency to black.
    public static func render(_ layout: StitchLayout, opaque: Bool) -> CGImage? {
        let scale = min(1, maxExportSide / max(layout.size.width, layout.size.height))
        let size = exportSize(layout.size)
        let base = layout.ops.first { $0.isBase }?.src.image.colorSpace
        let space = base.flatMap { $0.model == .rgb ? $0 : nil } ?? CGColorSpace(name: CGColorSpace.sRGB)!
        let alpha = opaque ? CGImageAlphaInfo.noneSkipLast : .premultipliedLast
        guard let context = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0,
                                      space: space, bitmapInfo: alpha.rawValue)
        else { return nil }
        // the layout's origin is the top left
        context.translateBy(x: 0, y: size.height)
        context.scaleBy(x: 1, y: -1)
        context.interpolationQuality = .high
        let white = CGColor(gray: 1, alpha: 1)
        func draw(_ image: CGImage, in rect: CGRect) {
            context.saveGState()
            context.translateBy(x: 0, y: rect.minY + rect.maxY)
            context.scaleBy(x: 1, y: -1)
            context.draw(image, in: rect)
            context.restoreGState()
        }
        if opaque {
            context.setFillColor(white)
            context.fill(CGRect(origin: .zero, size: size))
        }
        let transform = CGAffineTransform(scaleX: scale, y: scale)
        for op in layout.ops {
            let dest = op.dest.applying(transform)
            switch op.fit {
            case .matte:
                context.setFillColor(white)
                context.fill(dest)
                let s = min(dest.width / op.src.pixelSize.width, dest.height / op.src.pixelSize.height)
                let w = op.src.pixelSize.width * s
                let h = op.src.pixelSize.height * s
                draw(op.src.image, in: CGRect(x: dest.midX - w / 2, y: dest.midY - h / 2, width: w, height: h))
            case .match:
                draw(op.src.image.cropping(to: op.source.integral) ?? op.src.image, in: dest)
            case .cheese:
                draw(op.src.image, in: dest)
            }
        }
        return context.makeImage()
    }
}
