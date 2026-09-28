import Foundation

/// Expressions in nerdamer's syntax (the algebra and graph calculators' input) as a tree, and the tree as it is written by hand.
public enum CanonMath {
    /// The brackets of `abs`, `floor` and `ceil`.
    public enum Fence: Sendable { case abs, floor, ceil }

    public indirect enum Node: Equatable, Sendable {
        case number(String)
        /// Italic when it is a letter; `pi` and `Infinity` show as signs.
        case symbol(String)
        /// Upright text: an operator's `d`, a relation's empty side.
        case word(String)
        /// A missing operand in unfinished input.
        case hole
        case negate(Node)
        /// Terms; a subtracted term is a `negate`.
        case sum([Node])
        case product([Node])
        case quotient(Node, Node)
        case power(Node, Node)
        case call(String, [Node])
        case factorial(Node)
        case relation(String, Node, Node)
        case sub(Node, String)
        case list([Node])
        /// Always in parentheses.
        case group(Node)
        case derivative(Node, variable: String)
        case integral(Node, variable: String)
    }

    // MARK: Parsing

    private enum Token: Equatable {
        case number(String)
        case name(String)
        case op(Character)
    }

    static let functions: Set<String> = [
        "sin", "cos", "tan", "sec", "csc", "cot", "asin", "acos", "atan", "sinh", "cosh", "tanh",
        "log", "ln", "log10", "exp", "sqrt", "abs",
    ]

    /// The tree of `text`; nil when there is nothing, or when input is left over that does not parse,
    /// such as an unopened bracket. An operand still to be typed is a `hole`, a bracket still open is closed.
    public static func parse(_ text: String) -> Node? {
        let tokens = tokenise(text)
        guard !tokens.isEmpty else { return nil }
        var parser = Parser(tokens: tokens)
        let node = parser.statement()
        return parser.at == tokens.count ? node : nil
    }

    private static func tokenise(_ text: String) -> [Token] {
        var tokens: [Token] = []
        var index = text.startIndex
        func scan(while test: (Character) -> Bool) -> String {
            let start = index
            while index < text.endIndex, test(text[index]) { index = text.index(after: index) }
            return String(text[start..<index])
        }
        while index < text.endIndex {
            let character = text[index]
            if character.isWhitespace {
                index = text.index(after: index)
            } else if character.isASCII && (character.isNumber || character == ".") {
                tokens.append(.number(scan { $0.isASCII && ($0.isNumber || $0 == ".") }))
            } else if character.isLetter || character == "_" {
                tokens.append(.name(scan { $0.isLetter || $0 == "_" || $0.isASCII && $0.isNumber }))
            } else {
                index = text.index(after: index)
                switch character {
                case "\u{2212}": tokens.append(.op("-"))
                case "\u{00D7}", "\u{00B7}", "\u{22C5}": tokens.append(.op("*"))
                case "\u{00F7}": tokens.append(.op("/"))
                case "\u{221A}": tokens.append(.name("sqrt"))
                default: tokens.append(.op(character))
                }
            }
        }
        return tokens
    }

    private struct Parser {
        let tokens: [Token]
        var at = 0

        private var peek: Token? { at < tokens.count ? tokens[at] : nil }

        private mutating func take(_ op: Character) -> Bool {
            guard peek == .op(op) else { return false }
            at += 1
            return true
        }

        /// Starts an operand that may follow another with no sign between: `2x`, `2(x+1)`.
        private var startsImplicitFactor: Bool {
            switch peek {
            case .number, .name, .op("("), .op("["): true
            default: false
            }
        }

        mutating func statement() -> Node {
            let left = expression()
            return take("=") ? .relation("=", left, expression()) : left
        }

        private mutating func expression() -> Node {
            var terms = [term()]
            while true {
                if take("+") {
                    terms.append(term())
                } else if take("-") {
                    terms.append(.negate(term()))
                } else {
                    break
                }
            }
            return terms.count == 1 ? terms[0] : .sum(terms)
        }

        private mutating func term() -> Node {
            var node = unary()
            while true {
                if take("*") {
                    node = Self.multiply(node, unary())
                } else if take("/") {
                    node = .quotient(node, unary())
                } else if startsImplicitFactor {
                    node = Self.multiply(node, power())
                } else {
                    return node
                }
            }
        }

        private static func multiply(_ left: Node, _ right: Node) -> Node {
            if case .product(let factors) = left { return .product(factors + [right]) }
            return .product([left, right])
        }

        private mutating func unary() -> Node {
            if take("-") { return .negate(unary()) }
            if take("+") { return unary() }
            return power()
        }

        // right associative
        private mutating func power() -> Node {
            let base = postfix()
            return take("^") ? .power(base, unary()) : base
        }

        private mutating func postfix() -> Node {
            var node = primary()
            while take("!") { node = .factorial(node) }
            return node
        }

        private mutating func primary() -> Node {
            switch peek {
            case .number(let digits):
                at += 1
                return .number(digits)
            case .name(let name):
                at += 1
                if take("(") { return .call(name, arguments(closing: ")")) }
                if CanonMath.functions.contains(name), startsImplicitFactor { return .call(name, [power()]) }
                return .symbol(name)
            case .op("("):
                at += 1
                let inner = statement()
                _ = take(")")
                return inner
            case .op("["):
                at += 1
                return .list(arguments(closing: "]"))
            case .op("|"):
                at += 1
                let inner = expression()
                _ = take("|")
                return .call("abs", [inner])
            default:
                return .hole
            }
        }

        private mutating func arguments(closing: Character) -> [Node] {
            if take(closing) { return [] }
            var items = [statement()]
            while take(",") { items.append(statement()) }
            _ = take(closing)
            return items
        }
    }

    // MARK: Presentation

    private static let constants: Set<String> = ["e", "pi", "i", "Infinity"]
    private static let half = Node.quotient(.number("1"), .number("2"))

    /// A result as it is written by hand: powers of the variable falling, a positive term first, negative powers
    /// and rational coefficients as fractions, a power of a half as a root. Typed input is set as typed instead.
    public static func present(_ node: Node) -> Node {
        switch node {
        case .sum(let terms):
            var flat: [Node] = []
            for term in terms.map(present) {
                if case .sum(let inner) = term { flat += inner } else { flat.append(term) }
            }
            var ordered = flat.enumerated()
                .sorted { degree($0.element) != degree($1.element) ? degree($0.element) > degree($1.element) : $0.offset < $1.offset }
                .map(\.element)
            if isNegative(ordered[0]), let positive = ordered.firstIndex(where: { !isNegative($0) }) {
                ordered.insert(ordered.remove(at: positive), at: 0)
            }
            return .sum(ordered)
        case .product(let factors):
            return product(factors.map(present))
        case .power(let base, let exponent):
            let base = present(base)
            let exponent = present(exponent)
            if exponent == half { return .call("sqrt", [base]) }
            if case .negate(let inner) = exponent {
                let denominator: Node = inner == .number("1") ? base : inner == half ? .call("sqrt", [base]) : .power(base, inner)
                return .quotient(.number("1"), denominator)
            }
            return .power(base, exponent)
        case .negate(let inner):
            let inner = present(inner)
            if case .negate(let twice) = inner { return twice }
            return .negate(inner)
        case .quotient(let top, let bottom):
            return product([.quotient(present(top), present(bottom))])
        case .call(let name, let arguments):
            return .call(name, arguments.map(present))
        case .factorial(let inner):
            return .factorial(present(inner))
        case .relation(let op, let left, let right):
            return .relation(op, present(left), present(right))
        case .list(let items):
            return .list(items.map(present))
        default:
            return node
        }
    }

    /// Factors split over a fraction bar, with the sign pulled out front and numbers before letters before functions.
    private static func product(_ factors: [Node]) -> Node {
        var negative = false
        var top: [Node] = []
        var bottom: [Node] = []
        var queue = factors
        while !queue.isEmpty {
            var factor = queue.removeFirst()
            while case .negate(let inner) = factor {
                negative.toggle()
                factor = inner
            }
            switch factor {
            case .product(let inner):
                queue.insert(contentsOf: inner, at: 0)
            case .quotient(var above, let below):
                while case .negate(let inner) = above {
                    negative.toggle()
                    above = inner
                }
                if case .product(let inner) = above { top += inner } else if above != .number("1") { top.append(above) }
                if case .product(let inner) = below { bottom += inner } else { bottom.append(below) }
            default:
                top.append(factor)
            }
        }
        func joined(_ nodes: [Node]) -> Node {
            let ordered = nodes.enumerated().sorted { rank($0.element) != rank($1.element) ? rank($0.element) < rank($1.element) : $0.offset < $1.offset }.map(\.element)
            return ordered.isEmpty ? .number("1") : ordered.count == 1 ? ordered[0] : .product(ordered)
        }
        let body = bottom.isEmpty ? joined(top) : .quotient(joined(top), joined(bottom))
        return negative ? .negate(body) : body
    }

    private static func rank(_ node: Node) -> Int {
        switch node {
        case .number: 0
        case .symbol(let name) where !constants.contains(name): 1
        case .power(.symbol(let name), .number) where !constants.contains(name): 1
        case .sum: 3
        default: 2
        }
    }

    private static func isNegative(_ node: Node) -> Bool {
        if case .negate = node { return true }
        return false
    }

    private static func value(_ node: Node) -> Double? {
        switch node {
        case .number(let digits): Double(digits)
        case .negate(let inner): value(inner).map { -$0 }
        case .quotient(let top, let bottom): value(top).flatMap { top in value(bottom).map { top / $0 } }
        default: nil
        }
    }

    /// Total power of the letters in a term; constants and functions count nothing.
    static func degree(_ node: Node) -> Double {
        switch node {
        case .symbol(let name): constants.contains(name) ? 0 : 1
        case .negate(let inner), .factorial(let inner): degree(inner)
        case .product(let factors): factors.map(degree).reduce(0, +)
        case .quotient(let top, let bottom): degree(top) - degree(bottom)
        case .power(let base, let exponent): value(exponent).map { degree(base) * $0 } ?? 0
        case .call("sqrt", let arguments): arguments.first.map { degree($0) / 2 } ?? 0
        case .sum(let terms): terms.map(degree).max() ?? 0
        default: 0
        }
    }
}
