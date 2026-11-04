import Foundation
import Testing
@testable import DelphiCore

// selfChecks assert; debug test builds only
@Test func devToolsEngines() {
    UUIDEngine.selfCheck()
    PasswordEngine.selfCheck()
    JSONFormatEngine.selfCheck()
    JWTEngine.selfCheck()
    CronEngine.selfCheck()
    HTTPStatusTable.selfCheck()
    RequestBuilderEngine.selfCheck()
    CipherEngine.selfCheck()
    TailwindCheatsheet.selfCheck()
    EncoderEngine.selfCheck()
    BaseNumber.selfCheck()
    BarcodeMatrixExtractor.selfCheck()
    MorseEngine.selfCheck()
    RegexTesterEngine.selfCheck()
    BitRegroup.selfCheck()
}

@Test func textDiff() {
    let lines = TextDiffer.diff(left: "a\nb\nc", right: "a\nc\nd")
    #expect(lines == [
        .unchanged(text: "a", leftIndex: 0, rightIndex: 0),
        .removed(text: "b", leftIndex: 1),
        .unchanged(text: "c", leftIndex: 2, rightIndex: 1),
        .added(text: "d", rightIndex: 2),
    ])
}
