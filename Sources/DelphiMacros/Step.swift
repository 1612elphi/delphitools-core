import Foundation

public enum Step: Codable, Hashable, Sendable {
    case key(chord: KeyChord)
    case type(text: String)
    case appOpen(bundleID: String)
    case appQuit(bundleID: String)
    case appFocus(bundleID: String)
    case appHide(bundleID: String)
    case shell(command: String, timeout: Double)
    case applescript(source: String)
    case shortcut(name: String)
    case url(url: URL)
    case wait(ms: Int)
}

public struct KeyChord: Codable, Hashable, Sendable {
    /// macOS virtual key code (`kVK_*`).
    public var keyCode: UInt16
    public var modifiers: [Modifier]

    public init(keyCode: UInt16, modifiers: [Modifier]) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }
}

public enum Modifier: String, Codable, Hashable, Sendable {
    case command, shift, option, control, function
}
