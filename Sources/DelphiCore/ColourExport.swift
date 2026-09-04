import Foundation

public struct ColourExportFormat: Identifiable, Codable, Hashable {
    public let id: String
    public var name: String
    public var group: String
    public var template: String

    public init(id: String, name: String, group: String, template: String) {
        self.id = id
        self.name = name
        self.group = group
        self.template = template
    }

    public func format(_ colour: DelphiColour) -> String {
        ColourTemplate.render(template, colour)
    }
}

public struct ColourExportGroup: Identifiable {
    public let name: String
    public let formats: [ColourExportFormat]

    public init(name: String, formats: [ColourExportFormat]) {
        self.name = name
        self.formats = formats
    }

    public var id: String { name }
}

// templates double as presets
public enum ColourExport {
    public static let all: [ColourExportFormat] = [
        f("hex", "HEX", "CSS", "%[hex]"),
        f("hexa", "HEXA", "CSS", "%[hexa]"),
        f("dec-rgb", "Dec RGB", "CSS", "%[r255], %[g255], %[b255]"),
        f("css-rgb", "RGB", "CSS", "rgb(%[r255], %[g255], %[b255])"),
        f("css-rgba", "RGBA", "CSS", "rgba(%[r255], %[g255], %[b255], %[alpha])"),
        f("css-hsl", "HSL", "CSS", "hsl(%[hsl_h360], %[hsl_s100]%, %[hsl_l100]%)"),
        f("css-hsla", "HSLA", "CSS", "hsla(%[hsl_h360], %[hsl_s100]%, %[hsl_l100]%, %[alpha])"),
        f("css-p3", "Display P3", "CSS", "color(display-p3 %[p3_r] %[p3_g] %[p3_b])"),
        f("css-lab", "LAB", "CSS", "lab(%[lab_l] %[lab_a] %[lab_b])"),
        f("css-lch", "LCH", "CSS", "lch(%[lch_l] %[lch_c] %[lch_h])"),
        f("css-oklab", "OKLAB", "CSS", "oklab(%[oklab_l] %[oklab_a] %[oklab_b])"),
        f("css-oklch", "OKLCH", "CSS", "oklch(%[oklch_l] %[oklch_c] %[oklch_h])"),
        f("swiftui-rgb", "SwiftUI RGB", "Swift", "Color(red: %[r], green: %[g], blue: %[b])"),
        f("swiftui-hsb", "SwiftUI HSB", "Swift", "Color(hue: %[hsb_h], saturation: %[hsb_s], brightness: %[hsb_b])"),
        f("swift-literal", "Colour literal", "Swift", "#colorLiteral(red: %[r], green: %[g], blue: %[b], alpha: %[alpha])"),
        f("nscolor-rgb", "NSColor RGB", "Swift", "NSColor(red: %[r], green: %[g], blue: %[b], alpha: %[alpha])"),
        f("nscolor-hsb", "NSColor HSB", "Swift", "NSColor(hue: %[hsb_h], saturation: %[hsb_s], brightness: %[hsb_b], alpha: %[alpha])"),
        f("uicolor-rgb", "UIColor RGB", "Swift", "UIColor(red: %[r], green: %[g], blue: %[b], alpha: %[alpha])"),
        f("uicolor-hsb", "UIColor HSB", "Swift", "UIColor(hue: %[hsb_h], saturation: %[hsb_s], brightness: %[hsb_b], alpha: %[alpha])"),
        f("objc-nscolor", "NSColor calibrated", "Objective-C", "[NSColor colorWithCalibratedRed:%[r] green:%[g] blue:%[b] alpha:%[alpha]]"),
        f("objc-uicolor", "UIColor", "Objective-C", "[UIColor colorWithRed:%[r] green:%[g] blue:%[b] alpha:%[alpha]]"),
        f("net-rgb", "RGB", ".NET", "Color.FromArgb(%[r255], %[g255], %[b255])"),
        f("net-argb", "ARGB", ".NET", "Color.FromArgb(%[alpha255], %[r255], %[g255], %[b255])"),
        f("java-rgb", "RGB", "Java", "new Color(%[r255], %[g255], %[b255])"),
        f("java-rgba", "RGBA", "Java", "new Color(%[r255], %[g255], %[b255], %[alpha255])"),
        f("android-rgb", "RGB", "Android", "Color.rgb(%[r255], %[g255], %[b255])"),
        f("android-argb", "ARGB", "Android", "Color.argb(%[alpha255], %[r255], %[g255], %[b255])"),
    ]

    public static let groups: [ColourExportGroup] = grouped(all)

    public static func format(_ id: String) -> ColourExportFormat? {
        all.first { $0.id == id }
    }

    // first-appearance order
    public static func grouped(_ formats: [ColourExportFormat]) -> [ColourExportGroup] {
        var names: [String] = []
        for format in formats where !names.contains(format.group) { names.append(format.group) }
        return names.map { name in ColourExportGroup(name: name, formats: formats.filter { $0.group == name }) }
    }

    private static func f(_ id: String, _ name: String, _ group: String, _ template: String) -> ColourExportFormat {
        ColourExportFormat(id: id, name: name, group: group, template: template)
    }
}

extension DelphiColour {
    public var hexa: String {
        hex + String(format: "%02X", alpha255)
    }

    public var alpha255: Int {
        Int(round(clamp01(a) * 255))
    }

    /// Hue 0–360, saturation and brightness 0–1.
    public var hsb: (h: Double, s: Double, b: Double) {
        let r0 = clamp01(r), g0 = clamp01(g), b0 = clamp01(b)
        let cmax = max(r0, g0, b0)
        let delta = cmax - min(r0, g0, b0)
        return (hsl.h, cmax > 0 ? delta / cmax : 0, cmax)
    }

    /// Gamma-encoded Display P3 components, 0–1 within gamut. Matrices: CSS Color 4, XYZ (D65) to linear P3.
    public var displayP3: (r: Double, g: Double, b: Double) {
        let c = xyz
        let lr = 2.4934969119 * c.x - 0.9313836179 * c.y - 0.4027107845 * c.z
        let lg = -0.8294889696 * c.x + 1.7626640603 * c.y + 0.0236246858 * c.z
        let lb = 0.0358458302 * c.x - 0.0761723893 * c.y + 0.9568845240 * c.z
        func encode(_ v: Double) -> Double {
            let c = max(0, v)
            return c <= 0.0031308 ? 12.92 * c : 1.055 * pow(c, 1 / 2.4) - 0.055
        }
        return (encode(lr), encode(lg), encode(lb))
    }
}
