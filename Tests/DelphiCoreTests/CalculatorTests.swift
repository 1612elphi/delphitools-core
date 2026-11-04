import Foundation
import Testing
@testable import DelphiCore

@Test func calculatorEngines() {
    UnitConverterTable.selfCheck()
    TimeCalcWorld.selfCheck()
    TimeCalcAxis.selfCheck()
}

@Test func worldLandLoads() {
    #expect(!TimeCalcWorld.land.isEmpty)
}
