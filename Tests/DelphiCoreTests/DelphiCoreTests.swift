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
