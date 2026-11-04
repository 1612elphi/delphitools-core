import CoreGraphics
import DelphiCore
import Foundation
import simd

/// Colour-managed conversions. RGB numbers belong to a working space; Lab, LCH, OKLab and OKLCH are computed from
/// its primaries and white (D65, as `DelphiColour` and the web tools do); CMYK goes through ICC profiles.
/// `DelphiColour`'s own conversions stay sRGB and unchanged; a colour here holds working-space numbers, unclamped.
public struct ColourManagement: Equatable, Sendable {

    public enum Working: String, CaseIterable, Sendable {
        case sRGB, displayP3, adobeRGB

        public var name: String {
            switch self {
            case .sRGB: "sRGB"
            case .displayP3: "Display P3"
            case .adobeRGB: "Adobe RGB (1998)"
            }
        }

        public var colourSpace: CGColorSpace {
            switch self {
            case .sRGB: Self.sRGBSpace
            case .displayP3: Self.displayP3Space
            case .adobeRGB: Self.adobeRGBSpace
            }
        }

        fileprivate var toXYZ: simd_double3x3 {
            switch self {
            case .sRGB: Self.sRGBToXYZ.to
            case .displayP3: Self.displayP3ToXYZ.to
            case .adobeRGB: Self.adobeRGBToXYZ.to
            }
        }

        fileprivate var fromXYZ: simd_double3x3 {
            switch self {
            case .sRGB: Self.sRGBToXYZ.from
            case .displayP3: Self.displayP3ToXYZ.from
            case .adobeRGB: Self.adobeRGBToXYZ.from
            }
        }

        private static let sRGBSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        private static let displayP3Space = CGColorSpace(name: CGColorSpace.displayP3)!
        private static let adobeRGBSpace = CGColorSpace(name: CGColorSpace.adobeRGB1998)!

        // d65: iec/smpte/adobe rgb specs
        private static let sRGBToXYZ = pair([[0.4124564, 0.3575761, 0.1804375], [0.2126729, 0.7151522, 0.0721750], [0.0193339, 0.1191920, 0.9503041]])
        private static let displayP3ToXYZ = pair([[0.4865709486, 0.2656676932, 0.1982172852], [0.2289745641, 0.6917385218, 0.0792869141], [0, 0.0451133819, 1.0439443689]])
        private static let adobeRGBToXYZ = pair([[0.5766690429, 0.1855582379, 0.1882286462], [0.2973449753, 0.6273635663, 0.0752914585], [0.0270313614, 0.0706888525, 0.9913375368]])

        private static func pair(_ rows: [SIMD3<Double>]) -> (to: simd_double3x3, from: simd_double3x3) {
            let matrix = simd_double3x3(rows: rows)
            return (matrix, matrix.inverse)
        }

        fileprivate func linear(_ v: Double) -> Double {
            let magnitude = abs(v)
            let result = switch self {
            case .sRGB, .displayP3: magnitude <= 0.04045 ? magnitude / 12.92 : pow((magnitude + 0.055) / 1.055, 2.4)
            case .adobeRGB: pow(magnitude, 563.0 / 256)
            }
            return v < 0 ? -result : result
        }

        fileprivate func encoded(_ v: Double) -> Double {
            let magnitude = abs(v)
            let result = switch self {
            case .sRGB, .displayP3: magnitude <= 0.0031308 ? magnitude * 12.92 : 1.055 * pow(magnitude, 1 / 2.4) - 0.055
            case .adobeRGB: pow(magnitude, 256.0 / 563)
            }
            return v < 0 ? -result : result
        }
    }

    /// CMYK printing conditions. Bundled profiles are from the ICC profile registry, unaltered.
    public enum Press: String, CaseIterable, Sendable {
        case fogra39, gracol2013, generic

        public var name: String {
            switch self {
            case .fogra39: "Coated FOGRA39"
            case .gracol2013: "GRACoL 2013"
            case .generic: "Generic CMYK"
            }
        }

        /// The profile's file name, or the system's profile.
        public var source: String {
            switch self {
            case .fogra39: "Coated_Fogra39L_VIGC_300.icc"
            case .gracol2013: "GRACoL2013_CRPC6.icc"
            case .generic: "Generic CMYK Profile"
            }
        }

        public var colourSpace: CGColorSpace? { Self.spaces[self] ?? nil }

        private static let spaces: [Press: CGColorSpace?] = Dictionary(uniqueKeysWithValues: allCases.map { press in
            guard press != .generic else { return (press, CGColorSpace(name: CGColorSpace.genericCMYK)) }
            let name = (press.source as NSString).deletingPathExtension
            let url = Bundle.main.url(forResource: name, withExtension: "icc") ?? Bundle.main.url(forResource: name, withExtension: "icc", subdirectory: "ICC")
            return (press, url.flatMap { try? Data(contentsOf: $0) }.flatMap { CGColorSpace(iccData: $0 as CFData) })
        })
    }

    public var working = Working.sRGB
    /// Reads CMYK that is typed or picked.
    public var cmykIn = Press.fogra39
    /// Writes the colour as CMYK.
    public var cmykOut = Press.fogra39

    public init(working: Working = .sRGB, cmykIn: Press = .fogra39, cmykOut: Press = .fogra39) {
        (self.working, self.cmykIn, self.cmykOut) = (working, cmykIn, cmykOut)
    }

    // MARK: Settings

    private static let keys = (working: "colourManagementWorking", cmykIn: "colourManagementCMYKIn", cmykOut: "colourManagementCMYKOut")

    public static var stored: ColourManagement {
        get {
            let defaults = UserDefaults.standard
            var management = ColourManagement()
            if let raw = defaults.string(forKey: keys.working), let working = Working(rawValue: raw) { management.working = working }
            if let raw = defaults.string(forKey: keys.cmykIn), let press = Press(rawValue: raw) { management.cmykIn = press }
            if let raw = defaults.string(forKey: keys.cmykOut), let press = Press(rawValue: raw) { management.cmykOut = press }
            return management
        }
        set {
            let defaults = UserDefaults.standard
            defaults.set(newValue.working.rawValue, forKey: keys.working)
            defaults.set(newValue.cmykIn.rawValue, forKey: keys.cmykIn)
            defaults.set(newValue.cmykOut.rawValue, forKey: keys.cmykOut)
        }
    }

    // MARK: RGB and XYZ

    public func xyz(_ colour: DelphiColour) -> SIMD3<Double> {
        working.toXYZ * SIMD3(working.linear(colour.r), working.linear(colour.g), working.linear(colour.b))
    }

    public func colour(xyz: SIMD3<Double>) -> DelphiColour {
        let linear = working.fromXYZ * xyz
        return DelphiColour(r: working.encoded(linear.x), g: working.encoded(linear.y), b: working.encoded(linear.z))
    }

    /// Inside the working space's gamut, with a little slack for rounding.
    public static func inGamut(_ colour: DelphiColour) -> Bool {
        [colour.r, colour.g, colour.b].allSatisfy { $0 >= -0.002 && $0 <= 1.002 }
    }

    /// The same colour as sRGB numbers, for views that draw sRGB.
    public func sRGB(_ colour: DelphiColour) -> DelphiColour {
        working == .sRGB ? colour : ColourManagement(working: .sRGB).colour(xyz: xyz(colour))
    }

    public func cgColor(_ colour: DelphiColour) -> CGColor {
        let rgb = [colour.r, colour.g, colour.b].map { CGFloat(min(max($0, 0), 1)) }
        return CGColor(colorSpace: working.colourSpace, components: rgb + [1])!
    }

    // MARK: CIE and OK

    private static let d65 = SIMD3(0.95047, 1.0, 1.08883)

    public func lab(_ colour: DelphiColour) -> SIMD3<Double> {
        let f = (xyz(colour) / Self.d65).map(Self.labF)
        return [116 * f.y - 16, 500 * (f.x - f.y), 200 * (f.y - f.z)]
    }

    public func colour(lab: SIMD3<Double>) -> DelphiColour {
        let fy = (lab.x + 16) / 116
        let f = SIMD3(lab.y / 500 + fy, fy, fy - lab.z / 200)
        return colour(xyz: f.map(Self.labFInverse) * Self.d65)
    }

    // oklab: ottosson 2020
    public func oklab(_ colour: DelphiColour) -> SIMD3<Double> {
        let lms = (Self.okLMS * (Self.xyzToLinearSRGB * xyz(colour))).map(cbrt)
        return Self.okLab * lms
    }

    public func colour(oklab: SIMD3<Double>) -> DelphiColour {
        let lms = (Self.labToLMS * oklab).map { $0 * $0 * $0 }
        return colour(xyz: Self.sRGBToXYZ * (Self.lmsToLinearSRGB * lms))
    }

    /// Lightness, chroma, hue in degrees 0..<360, from a Lab-like triple.
    public static func polar(_ lab: SIMD3<Double>) -> SIMD3<Double> {
        var hue = atan2(lab.z, lab.y) * 180 / .pi
        if hue < 0 { hue += 360 }
        return [lab.x, (lab.y * lab.y + lab.z * lab.z).squareRoot(), hue]
    }

    public static func cartesian(_ lch: SIMD3<Double>) -> SIMD3<Double> {
        let radians = lch.z * .pi / 180
        return [lch.x, lch.y * cos(radians), lch.y * sin(radians)]
    }

    private static let xyzToLinearSRGB = Working.sRGB.fromXYZ
    private static let sRGBToXYZ = Working.sRGB.toXYZ
    private static let okLMS = simd_double3x3(rows: [
        [0.4122214708, 0.5363325363, 0.0514459929], [0.2119034982, 0.6806995451, 0.1073969566], [0.0883024619, 0.2817188376, 0.6299787005],
    ])
    private static let okLab = simd_double3x3(rows: [
        [0.2104542553, 0.7936177850, -0.0040720468], [1.9779984951, -2.4285922050, 0.4505937099], [0.0259040371, 0.7827717662, -0.8086757660],
    ])

    private static let labToLMS = okLab.inverse
    private static let lmsToLinearSRGB = okLMS.inverse

    private static func labF(_ t: Double) -> Double {
        let delta = 6.0 / 29
        return t > delta * delta * delta ? cbrt(t) : t / (3 * delta * delta) + 4.0 / 29
    }

    private static func labFInverse(_ t: Double) -> Double {
        let delta = 6.0 / 29
        return t > delta ? t * t * t : 3 * delta * delta * (t - 4.0 / 29)
    }

    // MARK: CMYK

    // bpc shifts cyan (27.1)
    /// Ink coverage 0...1 through the output profile; nil when the profile is missing.
    public func cmyk(_ colour: DelphiColour) -> SIMD4<Double>? {
        guard let press = cmykOut.colourSpace,
              let converted = cgColor(colour).converted(to: press, intent: .relativeColorimetric, options: nil),
              let ink = converted.components, ink.count >= 4 else { return nil }
        return SIMD4(ink[0...3].map(Double.init))
    }

    /// Ink coverage 0...1 read through the input profile, or `profile`.
    public func colour(cmyk ink: SIMD4<Double>, profile: Press? = nil) -> DelphiColour? {
        let clamped = ink.clamped(lowerBound: .zero, upperBound: .one)
        guard let press = (profile ?? cmykIn).colourSpace,
              let source = CGColor(colorSpace: press, components: [clamped.x, clamped.y, clamped.z, clamped.w, 1].map { CGFloat($0) }),
              let converted = source.converted(to: working.colourSpace, intent: .relativeColorimetric, options: nil),
              let rgb = converted.components, rgb.count >= 3 else { return nil }
        return DelphiColour(r: Double(rgb[0]), g: Double(rgb[1]), b: Double(rgb[2]))
    }
}

private extension SIMD3 where Scalar == Double {
    func map(_ transform: (Double) -> Double) -> SIMD3<Double> { [transform(x), transform(y), transform(z)] }
}

#if DEBUG
extension ColourManagement {
    public static func selfCheck() {
        let blue = DelphiColour.fromHex("3B82F6")!
        let srgb = ColourManagement()
        assert(simd_length(srgb.lab(blue) - SIMD3(blue.lab.l, blue.lab.a, blue.lab.b)) < 1e-4)
        assert(simd_length(srgb.oklab(blue) - SIMD3(blue.oklab.l, blue.oklab.a, blue.oklab.b)) < 1e-4)
        assert(abs(srgb.colour(lab: srgb.lab(blue)).r - blue.r) < 1e-6)
        assert(abs(srgb.colour(oklab: srgb.oklab(blue)).b - blue.b) < 1e-6)

        // p3 red exceeds srgb
        let p3 = ColourManagement(working: .displayP3)
        let red = DelphiColour(r: 1, g: 0, b: 0)
        assert(!inGamut(p3.sRGB(red)))
        assert(abs(p3.lab(DelphiColour(r: 1, g: 1, b: 1)).x - 100) < 1e-3)
        let adobe = ColourManagement(working: .adobeRGB)
        assert(abs(adobe.colour(xyz: adobe.xyz(blue)).g - blue.g) < 1e-9)

        // photoshop: c100 = 0,160,227
        if let cyan = srgb.colour(cmyk: [1, 0, 0, 0], profile: .fogra39)?.rgb {
            assert(abs(cyan.g - 160) <= 2 && abs(cyan.b - 227) <= 2, "fogra39 cyan \(cyan)")
        }
        for press in Press.allCases {
            var management = ColourManagement()
            management.cmykIn = press
            management.cmykOut = press
            // profiles bundled by app
            guard press.colourSpace != nil else { continue }
            let paper = management.colour(cmyk: .zero)!
            assert(paper.r > 0.97 && paper.g > 0.97 && paper.b > 0.97, "\(press.name) paper")
            assert(management.cmyk(DelphiColour(r: 0, g: 0, b: 0))!.w > 0.6, "\(press.name) black")
            let tan = DelphiColour.fromHex("8A6F4E")!
            let back = management.colour(cmyk: management.cmyk(tan)!)!
            assert(simd_length(management.lab(back) - management.lab(tan)) < 3, "\(press.name) round trip")
        }
    }
}
#endif
