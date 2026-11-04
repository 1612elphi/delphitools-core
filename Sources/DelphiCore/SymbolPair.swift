import Foundation

/// A symbol and what an encoding turns it into, for a strip that sets one over the other.
public struct SymbolPair: Equatable, Sendable {
    public enum Face: Equatable, Sendable {
        case text(String)
        /// Dots and dashes, drawn as marks to scale.
        case morse(String)
        /// Five A/B letters, drawn as open and filled cells.
        case bacon(String)
    }

    public enum Kind: Sendable { case glyph, space, newline }

    public var top: Face
    public var bottom: Face
    public var key: String?
    public var changes = true
    public var kind = Kind.glyph

    public init(top: Face, bottom: Face, key: String? = nil, changes: Bool = true, kind: Kind = .glyph) {
        (self.top, self.bottom, self.key, self.changes, self.kind) = (top, bottom, key, changes, kind)
    }

    public static let space = SymbolPair(top: .text(" "), bottom: .text(" "), kind: .space)
    public static let newline = SymbolPair(top: .text(""), bottom: .text(""), kind: .newline)
}
