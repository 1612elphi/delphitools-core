import DelphiMacros
import Foundation
import Testing

// skala deck.json format
@Test func decodesSkalaSteps() throws {
    let json = #"""
    [{ "appFocus": { "bundleID": "com.apple.Safari" } },
     { "key": { "chord": { "keyCode": 49, "modifiers": ["command"] } } },
     { "shell": { "command": "true", "timeout": 5 } },
     { "wait": { "ms": 10 } }]
    """#
    let steps = try JSONDecoder().decode([Step].self, from: Data(json.utf8))
    #expect(steps == [
        .appFocus(bundleID: "com.apple.Safari"),
        .key(chord: KeyChord(keyCode: 49, modifiers: [.command])),
        .shell(command: "true", timeout: 5),
        .wait(ms: 10),
    ])
    let again = try JSONDecoder().decode([Step].self, from: JSONEncoder().encode(steps))
    #expect(again == steps)
}
