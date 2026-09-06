import DelphiCore
import Testing

@Test func hexRoundTrip() {
    let colour = DelphiColour.fromHex("#3A7D44")
    #expect(colour?.hex == "#3A7D44")
    #expect(colour?.rgb.g == 125)
}

@Test func contrastOfBlackOnWhite() {
    let ratio = DelphiColour.contrastRatio(DelphiColour(r: 0, g: 0, b: 0), DelphiColour(r: 1, g: 1, b: 1))
    #expect(abs(ratio - 21) < 0.01)
}

@Test func oklchRoundTrip() {
    let colour = DelphiColour.fromHex("#FF8800")!
    let ok = colour.oklch
    #expect(DelphiColour.fromOKLCH(l: ok.l, c: ok.c, h: ok.h).hex == "#FF8800")
}

@Test func bundledColourNamesLoad() {
    #expect(ColourNames.closest(hex: "#FF0000") != "Unknown")
}

@Test func mathExpression() {
    let expression = MathExpression("2x + sin(0) + 3")
    #expect(expression.isValid)
    #expect(expression.evaluate(x: 2) == 7)
    #expect(!MathExpression("2 +").isValid)
}

@Test func parseNotations() {
    #expect(DelphiColour.parse("#abc")?.hex == "#AABBCC")
    #expect(DelphiColour.parse("rgb(255, 136, 0)")?.hex == "#FF8800")
    #expect(DelphiColour.parse("hsl 32 100% 50%")?.hex == "#FF8800")
    #expect(DelphiColour.parse("oklch(0.7 0.15 30)") != nil)
    #expect(DelphiColour.parse("rgb(1, 2)") == nil)
    #expect(DelphiColour.parse("hello") == nil)
}

@Test func harmonyCounts() {
    let base = DelphiColour.fromHex("#3B82F6")!
    #expect(base.harmony(.triadic).count == 3)
    #expect(base.harmony(.monochromatic).count == 5)
    #expect(base.harmony(.complementary)[0].hex == base.hex)
}

@Test func tailwindLightnessDescends() {
    let shades = DelphiColour.fromHex("#3B82F6")!.tailwindShades(.classic)
    #expect(shades.map(\.step) == DelphiColour.tailwindSteps.map(\.step))
    let lightness = shades.map(\.colour.oklch.l)
    #expect(lightness == lightness.sorted(by: >))
}

@Test func contrastFixReachesTarget() {
    let grey = DelphiColour.fromHex("#888888")!
    let white = DelphiColour(r: 1, g: 1, b: 1)
    let fixed = grey.adjusted(toContrast: 7, against: white)
    #expect(DelphiColour.contrastRatio(fixed, white) >= 7)
}

@Test func paletteStrategiesHonourCount() {
    for strategy in PaletteStrategies.all {
        #expect(strategy.generator(7, nil).count == 7, "\(strategy.id)")
    }
}

@Test func exportFormats() {
    let blue = DelphiColour.fromHex("#3B82F6")!
    #expect(ColourExport.format("hexa")?.format(blue) == "#3B82F6FF")
    #expect(ColourExport.format("css-rgba")?.format(blue) == "rgba(59, 130, 246, 1)")
    #expect(ColourExport.format("swiftui-rgb")?.format(blue) == "Color(red: 0.231, green: 0.510, blue: 0.965)")
    #expect(ColourExport.format("net-argb")?.format(blue) == "Color.FromArgb(255, 59, 130, 246)")
    #expect(Set(ColourExport.all.map(\.id)).count == ColourExport.all.count)
    let red = DelphiColour(r: 1, g: 0, b: 0).hsb
    #expect(red.h == 0 && red.s == 1 && red.b == 1)
    let white = DelphiColour(r: 1, g: 1, b: 1).displayP3
    #expect(abs(white.r - 1) < 0.001 && abs(white.g - 1) < 0.001 && abs(white.b - 1) < 0.001)
}

@Test func notationsMapToTemplates() {
    let blue = DelphiColour.fromHex("#3B82F6")!
    for format in ColourFormat.allCases {
        #expect(ColourExport.format(format.exportID) != nil, "\(format.rawValue)")
        #expect(!format.formatted(blue).isEmpty)
    }
    #expect(ColourFormat.hex.formatted(blue) == "#3B82F6")
}

@Test func templateRendering() {
    let blue = DelphiColour.fromHex("#3B82F6")!
    #expect(ColourTemplate.render("%[hex_raw]/%[alpha100]/%[nope]/%[", blue) == "3B82F6/100/%[nope]/%[")
    #expect(ColourExport.format("css-hsl")?.format(blue) == blue.hslString)
    #expect(ColourExport.format("css-oklch")?.format(blue) == blue.oklchString)
    #expect(ColourExport.format("css-lab")?.format(blue) == blue.labString)
    let cmyk = DelphiColour(r: 1, g: 0, b: 0).cmyk
    #expect(cmyk.c == 0 && cmyk.m == 1 && cmyk.y == 1 && cmyk.k == 0)
    #expect(blue.tints(3).count == 3 && blue.shades(3).count == 3)
    #expect(blue.tints(3).last!.oklch.l > blue.oklch.l && blue.shades(3).last!.oklch.l < blue.oklch.l)
}

@Test func cleanLinks() {
    #expect(LinkCleaner.clean("https://example.com/a?x=1&utm_source=tw&fbclid=abc") == "https://example.com/a?x=1")
    #expect(LinkCleaner.clean("https://example.com/a?utm_source=tw#:~:text=hi") == "https://example.com/a")
    #expect(LinkCleaner.clean("https://example.com/a?q=a%20b#section") == "https://example.com/a?q=a%20b#section")
    #expect(LinkCleaner.clean("https://www.amazon.de/Some-Thing/dp/B08XYZ1234/ref=sr_1_3?crid=Q&keywords=k") == "https://www.amazon.de/dp/B08XYZ1234")
    #expect(LinkCleaner.clean("https://youtu.be/abc?si=xyz") == "https://youtu.be/abc")
    #expect(LinkCleaner.clean("https://example.com/?si=keep") == "https://example.com/?si=keep")
    #expect(LinkCleaner.clean("not a url") == "not a url")
}
