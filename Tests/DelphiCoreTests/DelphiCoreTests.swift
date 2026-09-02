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
