import JavaScriptCore
import SwiftUI

// MARK: - Data Types

public enum AlgebraOperation: String, CaseIterable, Identifiable {
    case simplify = "Simplify"
    case expand = "Expand"
    case factor = "Factor"
    case solve = "Solve"
    case derivative = "d/dx"
    case integral = "∫"

    public var id: String { rawValue }

    public var label: LocalizedStringKey {
        switch self {
        case .simplify: "Simplify"
        case .expand: "Expand"
        case .factor: "Factor"
        case .solve: "Solve"
        case .derivative: "d/dx"
        case .integral: "∫"
        }
    }

    public var needsVariable: Bool {
        switch self {
        case .solve, .derivative, .integral: return true
        default: return false
        }
    }

    public var placeholder: String {
        switch self {
        case .simplify: return "(x+1)^2 - x^2"
        case .expand: return "(x+1)^3"
        case .factor: return "x^2 - 4"
        case .solve: return "x^2 - 4 = 0"
        case .derivative: return "x^3"
        case .integral: return "x^2"
        }
    }

    public var examples: [String] {
        switch self {
        case .simplify: return ["(x+1)^2 - x^2", "sin(x)^2 + cos(x)^2", "(a*b)/(a*c)"]
        case .expand: return ["(x+1)^3", "(a+b)*(a-b)", "(x+y+z)^2"]
        case .factor: return ["x^2 - 4", "x^3 - 1", "x^2 + 5*x + 6"]
        case .solve: return ["x^2 - 4 = 0", "2*x + 3 = 7", "x^2 + x - 6 = 0"]
        case .derivative: return ["x^3", "sin(x)*cos(x)", "e^x * x^2"]
        case .integral: return ["x^2", "sin(x)", "1/x"]
        }
    }
}

public struct AlgebraResult {
    public let input: String
    public let operation: AlgebraOperation
    public let variable: String
    public let textOutput: String
    public let solutions: [String]?
    public let approxSolutions: [String]?

    /// Formatted display string including operation context.
    public var displayText: String {
        switch operation {
        case .derivative:
            return "d/d\(variable) [\(input)] = \(textOutput)"
        case .integral:
            return "∫ \(input) d\(variable) = \(textOutput)"
        case .solve:
            guard let sols = solutions, !sols.isEmpty else { return "No solution" }
            return sols.map { "\(variable) = \($0)" }.joined(separator: "\n")
        default:
            return textOutput
        }
    }

}

// MARK: - Error

public struct AlgebraError: Error, LocalizedError {
    public let message: String
    public var errorDescription: String? { message }
}

// MARK: - Engine

@MainActor
public final class AlgebraEngine {

    private let context: JSContext

    public init?() {
        guard let ctx = JSContext(),
              let url = Bundle.module.url(forResource: "nerdamer-all.min", withExtension: "js"),
              let js = try? String(contentsOf: url, encoding: .utf8) else { return nil }

        var loadFailed = false
        ctx.exceptionHandler = { _, _ in loadFailed = true }
        ctx.evaluateScript(js)
        guard !loadFailed else { return nil }
        ctx.exceptionHandler = { _, _ in }
        self.context = ctx
    }

    public func evaluate(expression: String, operation: AlgebraOperation, variable: String) -> Result<AlgebraResult, AlgebraError> {
        context.setObject(expression, forKeyedSubscript: "inputExpr" as NSString)
        context.setObject(variable, forKeyedSubscript: "inputVar" as NSString)

        let script = jsScript(for: operation)

        guard let jsResult = context.evaluateScript(script),
              let jsonString = jsResult.toString(),
              jsonString != "undefined",
              let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .failure(AlgebraError(message: "Failed to evaluate expression"))
        }

        if let error = json["error"] as? String {
            return .failure(AlgebraError(message: cleanError(error)))
        }

        let text = json["text"] as? String ?? ""
        let solutions = json["solutions"] as? [String]
        let approx = json["approx"] as? [String]

        return .success(AlgebraResult(
            input: expression,
            operation: operation,
            variable: variable,
            textOutput: text,
            solutions: solutions,
            approxSolutions: approx
        ))
    }

    // MARK: - Private

    private func jsScript(for operation: AlgebraOperation) -> String {
        switch operation {
        case .simplify:
            return wrap("var r = nerdamer(inputExpr); return JSON.stringify({ text: r.text('fractions') });")

        case .expand:
            return wrap("var r = nerdamer('expand(' + inputExpr + ')'); return JSON.stringify({ text: r.text('fractions') });")

        case .factor:
            return wrap("var r = nerdamer('factor(' + inputExpr + ')'); return JSON.stringify({ text: r.text('fractions') });")

        case .solve:
            return wrap("""
                var r = nerdamer.solve(inputExpr, inputVar);
                var text = r.toString();
                var arr = text.replace(/^\\[|\\]$/g, '').split(',').filter(function(s) { return s.length > 0; });
                var approx = arr.map(function(s) {
                    try {
                        var val = nerdamer(s).text('decimals');
                        var num = parseFloat(val);
                        return isNaN(num) ? val : num.toPrecision(10);
                    } catch(e) { return s; }
                });
                return JSON.stringify({ text: text, solutions: arr, approx: approx });
                """)

        case .derivative:
            return wrap("var r = nerdamer('diff(' + inputExpr + ',' + inputVar + ')'); return JSON.stringify({ text: r.text('fractions') });")

        case .integral:
            return wrap("""
                var r = nerdamer('integrate(' + inputExpr + ',' + inputVar + ')');
                return JSON.stringify({ text: r.text('fractions') + ' + C' });
                """)
        }
    }

    private func wrap(_ body: String) -> String {
        """
        (function() {
            try {
                \(body)
            } catch(e) {
                return JSON.stringify({ error: e.message || String(e) });
            }
        })()
        """
    }

    private func cleanError(_ error: String) -> String {
        if let range = error.range(of: "\n") {
            return String(error[error.startIndex..<range.lowerBound])
        }
        return error
    }
}
