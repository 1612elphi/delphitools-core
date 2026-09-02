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
}

public struct MathTokeniser {

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
                if let val = Double(numStr) {
                    tokens.append(.number(val))
                }
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
                case "sin", "cos", "tan", "asin", "acos", "atan",
                     "sqrt", "abs", "log", "ln", "exp",
                     "floor", "ceil", "round":
                    tokens.append(.function(word))
                case "pi":
                    tokens.append(.constant("pi"))
                case "x":
                    tokens.append(.variable)
                case "e":
                    tokens.append(.constant("e"))
                default:
                    // Unknown word — treat each letter as variable or skip
                    // For resilience, just skip unknown identifiers
                    break
                }
                continue
            }

            // Unknown character, skip
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
///            | FUNCTION '(' expression ')'
///            | '(' expression ')'
/// ```
public indirect enum MathNode {
    case number(Double)
    case variable
    case binary(MathNode, Character, MathNode)
    case unary(Character, MathNode)
    case function(String, MathNode)
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
            guard let arg = parseExpression() else { return nil }
            guard current == .rightParen else { return nil }
            advance()
            return .function(name, arg)

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

    public static func evaluate(_ node: MathNode, x: Double) -> Double {
        switch node {
        case .number(let val):
            return val

        case .variable:
            return x

        case .binary(let left, let op, let right):
            let l = evaluate(left, x: x)
            let r = evaluate(right, x: x)
            switch op {
            case "+": return l + r
            case "-": return l - r
            case "*": return l * r
            case "/": return l / r
            case "^": return pow(l, r)
            default: return .nan
            }

        case .unary(let op, let operand):
            let val = evaluate(operand, x: x)
            if op == "-" { return -val }
            return val

        case .function(let name, let arg):
            let val = evaluate(arg, x: x)
            switch name {
            case "sin": return sin(val)
            case "cos": return cos(val)
            case "tan": return tan(val)
            case "asin": return asin(val)
            case "acos": return acos(val)
            case "atan": return atan(val)
            case "sqrt": return sqrt(val)
            case "abs": return abs(val)
            case "log": return log10(val)
            case "ln": return log(val)
            case "exp": return exp(val)
            case "floor": return floor(val)
            case "ceil": return ceil(val)
            case "round": return (val).rounded()
            default: return .nan
            }
        }
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

    public func evaluate(x: Double) -> Double {
        guard let ast else { return .nan }
        return MathEvaluator.evaluate(ast, x: x)
    }

    /// Test with x = 1 to verify the expression produces a finite result.
    private func testEvaluate() -> Bool {
        let result = evaluate(x: 1)
        return result.isFinite || result.isNaN // NaN is OK (e.g. sqrt(-1)), just not a crash
    }
}
