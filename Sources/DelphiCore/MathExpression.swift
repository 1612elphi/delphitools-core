import Foundation

// MARK: - Tokeniser

public enum MathToken: Equatable {
    case number(Double)
    case variable         // x
    case op(Character)    // + - * / ^
    case leftParen
    case rightParen
    case function(String) // sin, cos, etc.
    case constant(String) // pi, e
    case comma
    /// A word, number or character the tokeniser cannot read; no expression parses with one.
    case unknown(String)
}

public struct MathTokeniser {

    /// The functions the tokeniser reads, and how many arguments each takes. `log` is common with one argument,
    /// `log(a, b)` is the logarithm of `a` to base `b`; `nthroot(a, n)` is the `n`th root of `a`.
    public static let functions: [String: ClosedRange<Int>] = {
        let unary = ["sin", "cos", "tan", "sec", "csc", "cot", "asin", "acos", "atan", "asec", "acsc", "acot",
                     "sinh", "cosh", "tanh", "asinh", "acosh", "atanh",
                     "sqrt", "cbrt", "abs", "ln", "exp", "floor", "ceil", "round"]
        var table = Dictionary(uniqueKeysWithValues: unary.map { ($0, 1...1) })
        table["log"] = 1...2
        for binary in ["nthroot", "mod", "min", "max"] { table[binary] = 2...2 }
        return table
    }()

    public static func tokenise(_ input: String) -> [MathToken] {
        var tokens: [MathToken] = []
        let chars = Array(input.lowercased())
        var i = 0

        while i < chars.count {
            let c = chars[i]

            // Whitespace
            if c.isWhitespace { i += 1; continue }

            // Number (including decimals)
            if c.isNumber || (c == "." && i + 1 < chars.count && chars[i + 1].isNumber) {
                var numStr = String(c)
                i += 1
                while i < chars.count && (chars[i].isNumber || chars[i] == ".") {
                    numStr.append(chars[i])
                    i += 1
                }
                tokens.append(Double(numStr).map(MathToken.number) ?? .unknown(numStr))
                continue
            }

            // Operators
            if "+-*/^".contains(c) {
                tokens.append(.op(c))
                i += 1
                continue
            }

            // Parentheses
            if c == "(" { tokens.append(.leftParen); i += 1; continue }
            if c == ")" { tokens.append(.rightParen); i += 1; continue }

            // Comma
            if c == "," { tokens.append(.comma); i += 1; continue }

            // Letters → function, constant, or variable
            if c.isLetter {
                var word = ""
                while i < chars.count && chars[i].isLetter {
                    word.append(chars[i])
                    i += 1
                }

                switch word {
                case _ where functions[word] != nil:
                    tokens.append(.function(word))
                case "pi":
                    tokens.append(.constant("pi"))
                case "x":
                    tokens.append(.variable)
                case "e":
                    tokens.append(.constant("e"))
                default:
                    tokens.append(.unknown(word))
                }
                continue
            }

            tokens.append(.unknown(String(c)))
            i += 1
        }

        return insertImplicitMultiplication(tokens)
    }

    /// Insert `*` where multiplication is implied: `2x`, `2(`, `)(`, `x(`, `)2`, `pi x`, etc.
    private static func insertImplicitMultiplication(_ tokens: [MathToken]) -> [MathToken] {
        var result: [MathToken] = []

        for token in tokens {
            if let prev = result.last {
                let needsMul: Bool = {
                    // After: number, variable, constant, rightParen
                    // Before: number, variable, constant, leftParen, function
                    let afterValue: Bool = {
                        switch prev {
                        case .number, .variable, .constant, .rightParen: return true
                        default: return false
                        }
                    }()

                    let beforeValue: Bool = {
                        switch token {
                        case .number, .variable, .constant, .leftParen, .function: return true
                        default: return false
                        }
                    }()

                    return afterValue && beforeValue
                }()

                if needsMul {
                    result.append(.op("*"))
                }
            }
            result.append(token)
        }

        return result
    }
}

// MARK: - Parser (Recursive Descent)

/// Parses tokens into an AST.
///
/// Grammar (precedence low → high):
/// ```
/// expression = term (('+' | '-') term)*
/// term       = power (('*' | '/') power)*
/// power      = unary ('^' power)?          // right-associative
/// unary      = '-' unary | primary
/// primary    = NUMBER | VARIABLE | CONSTANT
///            | FUNCTION '(' expression (',' expression)* ')'
///            | '(' expression ')'
/// ```
public indirect enum MathNode {
    case number(Double)
    case variable
    case binary(MathNode, Character, MathNode)
    case unary(Character, MathNode)
    /// A function and its arguments, as many as `MathTokeniser.functions` allows it.
    case function(String, [MathNode])
}

public struct MathParser {

    private var tokens: [MathToken]
    private var pos: Int = 0

    public init(tokens: [MathToken]) {
        self.tokens = tokens
    }

    private var current: MathToken? {
        pos < tokens.count ? tokens[pos] : nil
    }

    private mutating func advance() {
        pos += 1
    }

    public mutating func parse() -> MathNode? {
        let node = parseExpression()
        // Should have consumed all tokens
        return pos == tokens.count ? node : nil
    }

    private mutating func parseExpression() -> MathNode? {
        guard var left = parseTerm() else { return nil }

        while let token = current, case .op(let c) = token, c == "+" || c == "-" {
            advance()
            guard let right = parseTerm() else { return nil }
            left = .binary(left, c, right)
        }

        return left
    }

    private mutating func parseTerm() -> MathNode? {
        guard var left = parsePower() else { return nil }

        while let token = current, case .op(let c) = token, c == "*" || c == "/" {
            advance()
            guard let right = parsePower() else { return nil }
            left = .binary(left, c, right)
        }

        return left
    }

    private mutating func parsePower() -> MathNode? {
        guard let base = parseUnary() else { return nil }

        if let token = current, case .op(let c) = token, c == "^" {
            advance()
            guard let exponent = parsePower() else { return nil } // right-associative
            return .binary(base, "^", exponent)
        }

        return base
    }

    private mutating func parseUnary() -> MathNode? {
        if let token = current, case .op(let c) = token, c == "-" {
            advance()
            guard let operand = parseUnary() else { return nil }
            return .unary("-", operand)
        }
        return parsePrimary()
    }

    private mutating func parsePrimary() -> MathNode? {
        guard let token = current else { return nil }

        switch token {
        case .number(let val):
            advance()
            return .number(val)

        case .variable:
            advance()
            return .variable

        case .constant(let name):
            advance()
            switch name {
            case "pi": return .number(.pi)
            case "e": return .number(M_E)
            default: return nil
            }

        case .function(let name):
            advance()
            // Expect '('
            guard current == .leftParen else { return nil }
            advance()
            var arguments: [MathNode] = []
            repeat {
                if !arguments.isEmpty { advance() }
                guard let argument = parseExpression() else { return nil }
                arguments.append(argument)
            } while current == .comma
            guard current == .rightParen, MathTokeniser.functions[name]?.contains(arguments.count) == true else { return nil }
            advance()
            return .function(name, arguments)

        case .leftParen:
            advance()
            guard let expr = parseExpression() else { return nil }
            guard current == .rightParen else { return nil }
            advance()
            return expr

        default:
            return nil
        }
    }
}

// MARK: - Evaluator

public struct MathEvaluator {

    public static func evaluate(_ node: MathNode, x: Double, degrees: Bool = false) -> Double {
        switch node {
        case .number(let val):
            return val

        case .variable:
            return x

        case .binary(let left, let op, let right):
            let l = evaluate(left, x: x, degrees: degrees)
            let r = evaluate(right, x: x, degrees: degrees)
            switch op {
            case "+": return l + r
            case "-": return l - r
            case "*": return l * r
            case "/": return l / r
            case "^": return pow(l, r)
            default: return .nan
            }

        case .unary(let op, let operand):
            let val = evaluate(operand, x: x, degrees: degrees)
            if op == "-" { return -val }
            return val

        case .function(let name, let arguments):
            return apply(name, arguments.map { evaluate($0, x: x, degrees: degrees) }, degrees: degrees)
        }
    }

    /// `name` of `values`; angles in and out are in degrees when `degrees` is set.
    public static func apply(_ name: String, _ values: [Double], degrees: Bool = false) -> Double {
        guard let a = values.first else { return .nan }
        let b = values.count > 1 ? values[1] : .nan
        let angle = degrees ? a * .pi / 180 : a
        let out = degrees ? 180 / Double.pi : 1
        switch name {
        case "sin": return sin(angle)
        case "cos": return cos(angle)
        case "tan": return tan(angle)
        case "sec": return 1 / cos(angle)
        case "csc": return 1 / sin(angle)
        case "cot": return cos(angle) / sin(angle)
        case "asin": return asin(a) * out
        case "acos": return acos(a) * out
        case "atan": return atan(a) * out
        case "asec": return acos(1 / a) * out
        case "acsc": return asin(1 / a) * out
        // nerdamer's acot, continuous through 0
        case "acot": return (.pi / 2 - atan(a)) * out
        case "sinh": return sinh(a)
        case "cosh": return cosh(a)
        case "tanh": return tanh(a)
        case "asinh": return asinh(a)
        case "acosh": return acosh(a)
        case "atanh": return atanh(a)
        case "sqrt": return sqrt(a)
        case "cbrt": return cbrt(a)
        case "nthroot": return root(a, b)
        case "abs": return abs(a)
        case "log": return values.count > 1 ? log(a) / log(b) : log10(a)
        case "ln": return log(a)
        case "exp": return exp(a)
        case "floor": return floor(a)
        case "ceil": return ceil(a)
        case "round": return a.rounded()
        // nerdamer's mod is JavaScript's %: the dividend's sign
        case "mod": return fmod(a, b)
        // Math.min and Math.max pass NaN on
        case "min": return a.isNaN || b.isNaN ? .nan : Swift.min(a, b)
        case "max": return a.isNaN || b.isNaN ? .nan : Swift.max(a, b)
        default: return .nan
        }
    }

    /// The `n`th root of `a`; real and negative for a negative `a` and an odd `n`, as nerdamer's, where `pow` is NaN.
    private static func root(_ a: Double, _ n: Double) -> Double {
        a < 0 && abs(n.truncatingRemainder(dividingBy: 2)) == 1 ? -pow(-a, 1 / n) : pow(a, 1 / n)
    }
}

// MARK: - Compiled Expression

/// A compiled, reusable math expression that can be evaluated at any x.
public struct MathExpression {

    public let source: String
    private let ast: MathNode?

    public var isValid: Bool { ast != nil && testEvaluate() }

    public init(_ source: String) {
        self.source = source
        let tokens = MathTokeniser.tokenise(source)
        var parser = MathParser(tokens: tokens)
        self.ast = parser.parse()
    }

    public func evaluate(x: Double, degrees: Bool = false) -> Double {
        guard let ast else { return .nan }
        return MathEvaluator.evaluate(ast, x: x, degrees: degrees)
    }

    /// Test with x = 1 to verify the expression produces a finite result.
    private func testEvaluate() -> Bool {
        let result = evaluate(x: 1)
        return result.isFinite || result.isNaN // NaN is OK (e.g. sqrt(-1)), just not a crash
    }
}
