import Foundation
import Testing
import DelphiCore

// no testable import: internal initialisers stay hidden
@MainActor @Test func appConstructsPublicTypes() {
    _ = IdentifierOptions()
    _ = IdentifierOptions(uppercase: true, stripHyphens: true)
    _ = PasswordEngine.PasswordSpec()
    _ = PasswordEngine.PassphraseSpec()
    _ = RequestSpec(method: "GET", url: "https://example.test", params: [RequestPair(key: "a", value: "1")], headers: [], body: "")
    _ = CipherParams()
    _ = BarcodeGeneratorViewModel()
    _ = MetaTagGeneratorViewModel()
    _ = TextScratchpadViewModel()
    _ = TextScratchpadViewModel(text: "a")
    _ = SymbolPair(top: .text("a"), bottom: .morse(".-"))
    _ = ColourManagement()
    _ = ColourManagement(working: .displayP3, cmykIn: .generic, cmykOut: .gracol2013)
    _ = PaletteDraft()
    _ = PaletteDraft(category: .mood, count: 4, seed: DelphiColour(r: 1, g: 0, b: 0))
}
