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

@Test func scientificEntry() {
    SciCalcEntry.selfCheck()
    SciCalcSyntax.selfCheck()
    let calculator = ScientificCalculator()
    #expect(calculator.evaluateExpression("sin(30)") == 0.5)
    #expect(calculator.evaluateExpression("2^10") == 1024 && calculator.evaluateExpression("5!") == 120)
    calculator.expression = "sqrt(16"
    calculator.evaluate()
    #expect(calculator.display == "4" && calculator.history.first?.expression == "sqrt(16)")
}
