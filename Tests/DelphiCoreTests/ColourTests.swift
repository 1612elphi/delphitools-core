import Testing
@testable import DelphiCore

// selfChecks assert; debug test builds only
@Test func colourEngines() {
    ColourManagement.selfCheck()
    ContrastRatio.selfCheck()
}
