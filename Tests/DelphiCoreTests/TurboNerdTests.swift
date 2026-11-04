import Foundation
import Testing
@testable import DelphiCore

@MainActor @Test func turboNerdEngines() {
    BrailleEngine.selfCheck()
    SpellingAlphabets.selfCheck()
    IPAEngine.selfCheck()
    ShavianEngine.selfCheck()
}

@Test func dictionariesLoad() async {
    let dictionary = await IPADictionary.load()
    #expect(dictionary["the"] != nil && dictionary.count > 100_000)
}

@MainActor @Test func shavianLooksUpDictionary() {
    let model = ShavianTransliteration()
    model.input = "the cat"
    model.loadDictionaries()
    guard case .word(let cat) = model.tokens.last else { return #expect(Bool(false)) }
    #expect(cat.source == .core && cat.shavian == "𐑒𐑨𐑑")
}
