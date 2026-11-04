import Testing
@testable import DelphiCore

@Test func socialSelfChecks() {
    SocialCrop.selfCheck()
    MatteSpec.selfCheck()
    ScrollEngine.selfCheck()
}
