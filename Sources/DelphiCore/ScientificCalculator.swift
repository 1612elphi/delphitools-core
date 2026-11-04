import Foundation

public final class ScientificCalculator {

    public enum AngleMode: String, CaseIterable, Identifiable {
        case deg = "DEG"
        case rad = "RAD"
        public var id: String { rawValue }

    }

    public struct HistoryEntry: Identifiable, Sendable {
        public let id = UUID()
        public let expression: String
        public let result: String
    }

    public struct MathConstant: Identifiable, Sendable {
        public enum Category: CaseIterable, Sendable { case mathematical, physical, chemical }

        public let id = UUID()
        public let name: String
        public let symbol: String
        public let value: Double
        public var unit: String?
        public var category = Category.mathematical
    }

    public var expression: String = ""
    public var display: String = "0"
    public var angleMode: AngleMode = .deg
    public var history: [HistoryEntry] = []
    public var lastAnswer: Double = 0

    public init() {}

    // web lib/math-constants.ts
    public static let constants: [MathConstant] = [
        MathConstant(name: "Pi", symbol: "π", value: .pi),
        MathConstant(name: "Euler's number", symbol: "e", value: M_E),
        MathConstant(name: "Golden ratio", symbol: "φ", value: 1.618033988749895),
        MathConstant(name: "Square root of 2", symbol: "√2", value: 2.0.squareRoot()),
        MathConstant(name: "Square root of 3", symbol: "√3", value: 1.7320508075688772),
        MathConstant(name: "Natural log of 2", symbol: "ln(2)", value: M_LN2),
        MathConstant(name: "Natural log of 10", symbol: "ln(10)", value: M_LN10),
        MathConstant(name: "Euler-Mascheroni", symbol: "γ", value: 0.5772156649015329),
        MathConstant(name: "Speed of light", symbol: "c", value: 299_792_458, unit: "m/s", category: .physical),
        MathConstant(name: "Planck constant", symbol: "h", value: 6.62607015e-34, unit: "J·s", category: .physical),
        MathConstant(name: "Gravitational constant", symbol: "G", value: 6.6743e-11, unit: "m³/(kg·s²)", category: .physical),
        MathConstant(name: "Boltzmann constant", symbol: "kB", value: 1.380649e-23, unit: "J/K", category: .physical),
        MathConstant(name: "Elementary charge", symbol: "e", value: 1.602176634e-19, unit: "C", category: .physical),
        MathConstant(name: "Electron mass", symbol: "mₑ", value: 9.1093837015e-31, unit: "kg", category: .physical),
        MathConstant(name: "Proton mass", symbol: "mₚ", value: 1.67262192369e-27, unit: "kg", category: .physical),
        MathConstant(name: "Standard gravity", symbol: "g", value: 9.80665, unit: "m/s²", category: .physical),
        MathConstant(name: "Avogadro constant", symbol: "Nₐ", value: 6.02214076e23, unit: "mol⁻¹", category: .chemical),
        MathConstant(name: "Gas constant", symbol: "R", value: 8.314462618, unit: "J/(mol·K)", category: .chemical),
        MathConstant(name: "Faraday constant", symbol: "F", value: 96485.33212, unit: "C/mol", category: .chemical),
    ]

    public func input(_ token: String) {
        switch token {
        case "C":
            expression = ""
            display = "0"
        case "⌫":
            if !expression.isEmpty {
                expression.removeLast()
                display = expression.isEmpty ? "0" : expression
            }
        case "=":
            evaluate()
        case "±":
            if expression.isEmpty || expression == "0" { return }
            if expression.hasPrefix("-") {
                expression.removeFirst()
            } else {
                expression = "-" + expression
            }
            display = expression
        case "Ans":
            let formatted = formatNumber(lastAnswer)
            expression += formatted
            display = expression
        case "x²":
            expression += "^2"
            display = expression
        case "xʸ":
            expression += "^"
            display = expression
        case "ʸ√x":
            expression += "root("
            display = expression
        case "10ˣ":
            expression += "10^"
            display = expression
        case "eˣ":
            expression += "e^"
            display = expression
        case "EE":
            expression += "e"
            display = expression
        case "sin", "cos", "tan", "asin", "acos", "atan", "log", "ln", "abs":
            expression += token + "("
            display = expression
        default:
            expression += token
            display = expression
        }
    }

    public func loadFromHistory(_ entry: HistoryEntry) {
        expression = entry.expression
        display = entry.expression
    }

    // MARK: - Evaluation

    public func evaluate() {
        guard !expression.isEmpty else { return }

        let openCount = expression.filter({ $0 == "(" }).count
        let closeCount = expression.filter({ $0 == ")" }).count
        if openCount > closeCount {
            expression += String(repeating: ")", count: openCount - closeCount)
        }

        let original = expression
        let result = evaluateExpression(expression)

        if result.isNaN || result.isInfinite {
            display = result.isNaN ? "Error" : (result > 0 ? "∞" : "-∞")
        } else {
            let formatted = formatNumber(result)
            display = formatted
            lastAnswer = result
            history.insert(HistoryEntry(expression: original, result: formatted), at: 0)
            if history.count > 20 { history.removeLast() }
            expression = formatted
        }
    }

    public func evaluateExpression(_ expr: String) -> Double {
        let chars = Array(expr)
        var pos = 0

        func peek() -> Character? {
            pos < chars.count ? chars[pos] : nil
        }

        func advance() -> Character? {
            guard pos < chars.count else { return nil }
            let c = chars[pos]
            pos += 1
            return c
        }

        func skipSpaces() {
            while let c = peek(), c == " " { pos += 1 }
        }

        func parseNumber() -> Double? {
            skipSpaces()
            var str = ""

            if peek() == "-" {
                str.append(advance()!)
            }

            while let c = peek(), c.isNumber || c == "." {
                str.append(advance()!)
            }

            if let c = peek(), c == "e" || c == "E" {
                str.append(advance()!)
                if let s = peek(), s == "+" || s == "-" {
                    str.append(advance()!)
                }
                while let c = peek(), c.isNumber {
                    str.append(advance()!)
                }
            }

            return Double(str)
        }

        func parseIdentifier() -> String {
            var name = ""
            while let c = peek(), c.isLetter {
                name.append(advance()!)
            }
            return name
        }

        func parseFactor() -> Double {
            skipSpaces()

            guard let c = peek() else { return .nan }

            if c == "(" {
                _ = advance()
                let val = parseAddSub()
                if peek() == ")" { _ = advance() }
                return val
            }

            if c.isLetter {
                let name = parseIdentifier()

                switch name {
                case "pi", "π": return .pi
                case "e": return M_E
                default: break
                }

                if peek() == "(" {
                    _ = advance()
                    let arg = parseAddSub()
                    if peek() == ")" { _ = advance() }

                    switch name {
                    case "sin": return cleanTrigResult(sin(toRadians(arg)))
                    case "cos": return cleanTrigResult(cos(toRadians(arg)))
                    case "tan":
                        let rad = toRadians(arg)
                        let cosVal = cos(rad)
                        if abs(cosVal) < 1e-12 { return .infinity }
                        return cleanTrigResult(sin(rad) / cosVal)
                    case "asin": return fromRadians(asin(arg))
                    case "acos": return fromRadians(acos(arg))
                    case "atan": return fromRadians(atan(arg))
                    case "sqrt", "√": return sqrt(arg)
                    case "log": return log10(arg)
                    case "ln": return log(arg)
                    case "abs": return abs(arg)
                    case "root":
                        // root(n, x): nth root
                        if peek() == "," {
                            _ = advance()
                            let x = parseAddSub()
                            if peek() == ")" { _ = advance() }
                            return pow(x, 1.0 / arg)
                        }
                        return sqrt(arg)
                    default: return .nan
                    }
                }
                return .nan
            }

            if c.isNumber || c == "." || c == "-" {
                return parseNumber() ?? .nan
            }

            if c == "|" {
                _ = advance()
                let val = parseAddSub()
                if peek() == "|" { _ = advance() }
                return abs(val)
            }

            return .nan
        }

        func parsePostfix() -> Double {
            var val = parseFactor()
            skipSpaces()
            if peek() == "!" {
                _ = advance()
                val = factorial(val)
            }
            return val
        }

        func parsePower() -> Double {
            var base = parsePostfix()
            skipSpaces()
            if peek() == "^" {
                _ = advance()
                let exp = parseFactor() // right-associative
                base = pow(base, exp)
            }
            return base
        }

        func parseMulDiv() -> Double {
            var left = parsePower()
            while true {
                skipSpaces()
                guard let op = peek() else { break }
                if op == "×" || op == "*" {
                    _ = advance()
                    left *= parsePower()
                } else if op == "÷" || op == "/" {
                    _ = advance()
                    left /= parsePower()
                } else if op == "%" {
                    _ = advance()
                    let right = parsePower()
                    left = left.truncatingRemainder(dividingBy: right)
                } else {
                    break
                }
            }
            return left
        }

        func parseAddSub() -> Double {
            var left = parseMulDiv()
            while true {
                skipSpaces()
                guard let op = peek() else { break }
                if op == "+" {
                    _ = advance()
                    left += parseMulDiv()
                } else if op == "-" {
                    _ = advance()
                    left -= parseMulDiv()
                } else {
                    break
                }
            }
            return left
        }

        let value = parseAddSub()
        skipSpaces()
        return pos == chars.count ? value : .nan
    }

    /// avoids cos(90°) residue
    private func toRadians(_ value: Double) -> Double {
        guard angleMode == .deg else { return value }
        return value * .pi / 180
    }

    private func fromRadians(_ value: Double) -> Double {
        angleMode == .deg ? value * 180 / .pi : value
    }

    /// trig noise near integers
    private func cleanTrigResult(_ value: Double) -> Double {
        if abs(value) < 1e-12 { return 0 }
        if abs(value - 1) < 1e-12 { return 1 }
        if abs(value + 1) < 1e-12 { return -1 }
        if abs(value - 0.5) < 1e-12 { return 0.5 }
        if abs(value + 0.5) < 1e-12 { return -0.5 }
        return value
    }

    private func factorial(_ n: Double) -> Double {
        guard (0...170).contains(n), n.rounded() == n else { return .nan }
        let intN = Int(n)
        if intN == 0 || intN == 1 { return 1 }
        var result: Double = 1
        for i in 2...intN { result *= Double(i) }
        return result
    }

    public func formatNumber(_ value: Double) -> String {
        if value == 0 { return "0" }
        if abs(value) >= 1e15 || (abs(value) < 1e-10 && value != 0) {
            return String(format: "%g", value)
        }
        let formatted = String(format: "%.10g", value)
        return formatted
    }
}

// MARK: - Entry

/// How a key press changes the expression text, apart from the evaluator.
public enum SciCalcEntry {
    public enum Kind: Sendable {
        /// A digit or point.
        case digit
        /// Starts a value: a function, a bracket, a constant, a recalled number.
        case factor
        /// Operators and everything that continues a value.
        case other
    }

    private static let factors: Set<String> = ["(", "sin", "cos", "tan", "asin", "acos", "atan", "log", "ln", "π", "e", "√", "ʸ√x", "10ˣ", "eˣ", "Ans", "Const"]

    public static func kind(of key: String) -> Kind {
        if key.count == 1, let character = key.first, character.isNumber || character == "." { return .digit }
        return factors.contains(key) ? .factor : .other
    }

    /// The evaluator's text for a key.
    public static func text(for key: String) -> String {
        switch key {
        case "x²": "^2"
        case "xʸ": "^"
        case "√": "sqrt("
        case "ʸ√x": "root("
        case "10ˣ": "10^"
        case "eˣ": "e^"
        case "EE": "e"
        case "|x|": "|"
        case "mod": "%"
        case "−": "-"
        case "sin", "cos", "tan", "asin", "acos", "atan", "log", "ln": key + "("
        default: key
        }
    }

    /// Appends `text`, with a multiplication sign where two values would otherwise meet: 2π is 2×π.
    public static func join(_ expression: String, _ text: String, kind: Kind) -> String {
        guard let last = expression.last, kind != .other else { return expression + text }
        let before = expression.dropLast().last
        // e after digit: EE
        let euler = last == "e" && !(before.map { $0.isNumber || $0 == "." } ?? false)
        let closes = last == ")" || last == "π" || last == "!" || euler
        let ends = closes || last.isNumber || last == "."
        return expression + ((kind == .digit ? closes : ends) ? "×" : "") + text
    }

    /// Changes the sign of the number being typed: 3+4 becomes 3−4, 3×4 becomes 3×−4. Nil when the expression does not end in a number.
    public static func toggledSign(_ expression: String) -> String? {
        var characters = Array(expression)
        guard let last = characters.last, last.isNumber || last == "." else { return nil }
        var start = characters.count
        while start > 0, characters[start - 1].isNumber || characters[start - 1] == "." { start -= 1 }
        guard start > 0 else { return "-" + expression }
        switch characters[start - 1] {
        case "-":
            let lead = start >= 2 ? characters[start - 2] : nil
            let exponent = lead == "e" && start >= 3 && (characters[start - 3].isNumber || characters[start - 3] == ".")
            if lead == nil || exponent || "+-×÷^(%,|".contains(lead!) {
                characters.remove(at: start - 1)
            } else {
                characters[start - 1] = "+"
            }
        case "+":
            characters[start - 1] = "-"
        default:
            characters.insert("-", at: start)
        }
        return String(characters)
    }

    public static func openParens(_ expression: String) -> Int {
        max(0, expression.filter { $0 == "(" }.count - expression.filter { $0 == ")" }.count)
    }

    /// `%g` output with a real minus, and a power of ten written as ×10 with a raised exponent.
    public static func written(_ text: String) -> String {
        let parts = parts(text)
        guard let exponent = parts.exponent else { return parts.mantissa }
        let raised: [Character: Character] = ["0": "⁰", "1": "¹", "2": "²", "3": "³", "4": "⁴", "5": "⁵", "6": "⁶", "7": "⁷", "8": "⁸", "9": "⁹", "−": "⁻"]
        return parts.mantissa + " × 10" + String(exponent.map { raised[$0] ?? $0 })
    }

    /// Splits `%g` output at its exponent: "1.5e+15" is 1.5 and 15. Minus signs become the real minus.
    public static func parts(_ text: String) -> (mantissa: String, exponent: String?) {
        let halves = text.split(separator: "e", maxSplits: 1)
        let mantissa = String(halves.first ?? "").replacingOccurrences(of: "-", with: "−")
        guard halves.count == 2, let power = Int(halves[1]) else { return (text.replacingOccurrences(of: "-", with: "−"), nil) }
        return (mantissa, String(power).replacingOccurrences(of: "-", with: "−"))
    }

    /// Characters followed by a thousands gap, drawn with kerning so a copy stays plain: 1234567.5 has gaps after 1 and 4.
    public static func groupBreaks(_ mantissa: String) -> [Int] {
        let characters = Array(mantissa)
        let lead = characters.first == "−" ? 1 : 0
        let digits = characters[lead...].prefix { $0.isNumber }.count
        guard digits >= 5 else { return [] }
        return (0..<digits - 1).filter { (digits - 1 - $0) % 3 == 0 }.map { $0 + lead }
    }

    #if DEBUG
    public static func selfCheck() {
        assert(join("2", "π", kind: .factor) == "2×π" && join("2", "sin(", kind: .factor) == "2×sin(")
        assert(join("(3)", "4", kind: .digit) == "(3)×4" && join("π", "2", kind: .digit) == "π×2")
        assert(join("2e", "3", kind: .digit) == "2e3" && join("e", "2", kind: .digit) == "e×2" && join("2+", "π", kind: .factor) == "2+π")
        assert(join("12", "+", kind: .other) == "12+" && join("", "π", kind: .factor) == "π")
        assert(toggledSign("3+4") == "3-4" && toggledSign("3-4") == "3+4" && toggledSign("3×4") == "3×-4")
        assert(toggledSign("3×-4") == "3×4" && toggledSign("12") == "-12" && toggledSign("-12") == "12")
        assert(toggledSign("1.5e3") == "1.5e-3" && toggledSign("1.5e-3") == "1.5e3" && toggledSign("sin(") == nil)
        assert(openParens("sin(cos(4") == 2 && openParens("(1))") == 0)
        assert(written("6.62607015e-34") == "6.62607015 × 10⁻³⁴" && written("-9.80665") == "−9.80665")
        assert(kind(of: "7") == .digit && kind(of: "sin") == .factor && kind(of: "+") == .other)
        assert(parts("1.234567891e+15") == ("1.234567891", "15") && parts("-2e-05") == ("−2", "−5"))
        assert(parts("0.25") == ("0.25", nil) && parts("-7") == ("−7", nil) && parts("Error") == ("Error", nil))
        assert(groupBreaks("1234567.5") == [0, 3] && groupBreaks("−12345") == [2] && groupBreaks("1234") == [])
    }
    #endif
}


// MARK: - Syntax

/// The expression as a calculator prints it: real minus and times signs, √ for sqrt, exponents raised, brackets still to close greyed.
public enum SciCalcSyntax {
    public enum Kind: Sendable { case number, function, operation, bracket, ghost }

    public struct Piece: Equatable, Sendable {
        public var text: String
        public var kind: Kind
        public var raised = false

        public init(text: String, kind: Kind, raised: Bool = false) {
            (self.text, self.kind, self.raised) = (text, kind, raised)
        }
    }

    public static func pieces(_ raw: String) -> [Piece] {
        let characters = Array(raw)
        func numeric(_ index: Int) -> Bool {
            characters.indices.contains(index) && (characters[index].isNumber || characters[index] == ".")
        }
        func run(from start: Int, while test: (Int) -> Bool) -> Int {
            var end = start
            while end < characters.count, test(end) { end += 1 }
            return end
        }
        var pieces: [Piece] = []
        var index = 0
        while index < characters.count {
            let character = characters[index]
            if numeric(index) {
                let end = run(from: index, while: numeric)
                pieces.append(Piece(text: String(characters[index..<end]), kind: .number))
                index = end
            } else if character.isLetter {
                let end = run(from: index) { characters[$0].isLetter }
                let word = String(characters[index..<end])
                if word == "e", numeric(index - 1) {
                    pieces.append(Piece(text: "E", kind: .operation))
                } else if word == "e" || word == "π" {
                    pieces.append(Piece(text: word, kind: .number))
                } else {
                    pieces.append(Piece(text: ["sqrt": "√", "root": "ʸ√"][word] ?? word, kind: .function))
                }
                index = end
            } else if character == "^", numeric(index + 1) || characters.indices.contains(index + 1) && characters[index + 1] == "-" && numeric(index + 2) {
                let end = run(from: index + (characters[index + 1] == "-" ? 2 : 1), while: numeric)
                pieces.append(Piece(text: String(characters[index + 1..<end]).replacingOccurrences(of: "-", with: "−"), kind: .number, raised: true))
                index = end
            } else {
                let text = ["-": "−", "*": "×", "/": "÷", "%": " mod "][character] ?? String(character)
                pieces.append(Piece(text: text, kind: "()|,".contains(character) ? .bracket : .operation))
                index += 1
            }
        }
        return pieces
    }

    #if DEBUG
    public static func selfCheck() {
        func plain(_ raw: String) -> String { pieces(raw).map(\.text).joined() }
        assert(plain("sqrt(2)*3-1") == "√(2)×3−1" && plain("5%3") == "5 mod 3" && plain("root(3,8)") == "ʸ√(3,8)")
        assert(plain("1.5e-3") == "1.5E−3" && plain("2×e^2") == "2×e2" && plain("2^-3") == "2−3" && plain("2^") == "2^")
        assert(pieces("2^10").last == Piece(text: "10", kind: .number, raised: true))
        assert(pieces("sin(π").map(\.kind) == [.function, .bracket, .number])
    }
    #endif
}
