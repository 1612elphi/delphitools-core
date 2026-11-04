import Foundation
import Testing
@testable import DelphiCore

@Test func typographyEngines() {
    TypeUnits.selfCheck()
    WordCount.selfCheck()
    PaperQuery.selfCheck()
    LargeTypeEngine.selfCheck()
    LargeTypeLayout.selfCheck()
}
