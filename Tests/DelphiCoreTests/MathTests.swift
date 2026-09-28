import DelphiCore
import Foundation
import Testing

private func value(_ text: String, _ x: Double = 0) -> Double {
    MathExpression(text).evaluate(x: x)
}

private func same(_ a: Double, _ b: Double) -> Bool {
    a.isNaN && b.isNaN || a == b || abs(a - b) <= 1e-9 * max(1, abs(b))
}

@Test func functionsMatchFoundation() {
    let unary: [String: (Double) -> Double] = [
        "sin": sin, "cos": cos, "tan": tan, "asin": asin, "acos": acos, "atan": atan, "ln": log, "log": log10,
        "sec": { 1 / cos($0) }, "csc": { 1 / sin($0) }, "cot": { cos($0) / sin($0) },
        "asec": { acos(1 / $0) }, "acsc": { asin(1 / $0) }, "acot": { .pi / 2 - atan($0) },
        "sinh": sinh, "cosh": cosh, "tanh": tanh, "asinh": asinh, "acosh": acosh, "atanh": atanh,
        "sqrt": sqrt, "cbrt": cbrt, "abs": abs, "exp": exp, "floor": floor, "ceil": ceil, "round": { $0.rounded() },
    ]
    #expect(Set(unary.keys) == Set(MathTokeniser.functions.filter { $0.value.contains(1) }.keys))
    for (name, reference) in unary {
        let expression = MathExpression("\(name)(x)")
        // isValid refuses atanh, infinite at x = 1
        #expect(expression.isValid || name == "atanh", "\(name)")
        for x in [-2.5, -1, -0.5, 0, 0.5, 1.7, 3] {
            #expect(same(expression.evaluate(x: x), reference(x)), "\(name) at \(x)")
        }
    }
    for x in [-2.5, -1, 0.5, 1.7, 3] {
        #expect(same(value("mod(x, 3)", x), fmod(x, 3)) && same(value("min(x, 1)", x), min(x, 1)) && same(value("max(x, 1)", x), max(x, 1)))
    }
}

@Test func domainsAndAsymptotes() {
    #expect(same(value("sec(0.5)"), 1.139493927324549))
    #expect(value("csc(0)").isInfinite && value("cot(0)").isInfinite && value("1/x").isInfinite)
    #expect(value("sec(x)", .pi / 2 - 1e-6) > 1e5 && value("sec(x)", .pi / 2 + 1e-6) < -1e5)
    #expect(value("cot(x)", 1e-9) > 1e8 && value("cot(x)", -1e-9) < -1e8)
    #expect(value("csc(x)", 1e-9) > 1e8 && value("csc(x)", -1e-9) < -1e8)
    #expect(value("ln(0)") == -.infinity && value("ln(-1)").isNaN && value("sqrt(-1)").isNaN)
    #expect(value("atanh(1)") == .infinity && value("atanh(2)").isNaN && value("acosh(0.5)").isNaN)
    #expect(value("asec(0.5)").isNaN && value("acsc(0)").isNaN && value("acosh(1)") == 0)
    #expect(same(value("acot(0)"), .pi / 2) && same(value("acot(-1)"), 3 * .pi / 4))
}

@Test func extremes() {
    #expect(same(value("asinh(x)", -1e8), asinh(-1e8)))
    #expect(value("tanh(x)", 800) == 1 && value("tanh(x)", -800) == -1)
    #expect(value("min(x, 1)", 1e20) == 1 && value("max(x, 1)", 1e-20) == 1 && value("min(x, 1)", 1) == 1)
    #expect(value("min(x, 1)", .nan).isNaN && value("max(1, x)", .nan).isNaN)
    // JavaScript %: the dividend's sign
    #expect(same(value("mod(x, 3)", -7.5), -1.5) && value("mod(x, 0)", 2).isNaN)
}

@Test func logsAndRoots() {
    #expect(same(value("ln(100)"), log(100)) && same(value("log(100)"), 2))
    #expect(same(value("log(8, 2)"), 3) && same(value("log(1000, 10)"), 3))
    #expect(same(value("cbrt(x)", -8), -2) && value("cbrt(0)") == 0)
    #expect(same(value("nthroot(x, 5)", -32), -2) && value("nthroot(x, 4)", -16).isNaN && same(value("nthroot(16, 4)"), 2))
    #expect(same(value("nthroot(8, 3)"), 2) && same(value("nthroot(x, -3)", -8), -0.5))
}

@Test func impliedProductsAndPowers() {
    #expect(same(value("2pi"), 2 * .pi) && same(value("e"), M_E))
    #expect(same(value("3x sin(x)", 2), 6 * sin(2)))
    #expect(same(value("(x+1)(x-1)", 3), 8))
    #expect(same(value("x^(x+1)", 2), 8) && same(value("x^-2", 2), 0.25))
    #expect(value("-x^2", 2) == 4, "a leading minus binds tighter than ^")
}

@Test func degrees() {
    let degrees = { (text: String) in MathExpression(text).evaluate(x: 0, degrees: true) }
    #expect(same(degrees("sec(60)"), 2) && same(degrees("cot(45)"), 1) && same(degrees("csc(30)"), 2))
    #expect(same(degrees("acot(1)"), 45) && same(degrees("asec(2)"), 60) && same(degrees("acsc(2)"), 30))
    #expect(same(degrees("sinh(1)"), sinh(1)), "hyperbolic functions take no angle")
}

@Test func unreadableInputIsInvalid() {
    for text in ["foo(x)", "2 # 3", "1.2.3x", "sin(x, 1)", "mod(x)", "log(x, 2, 3)", "min()", "xsin(x)", "y"] {
        #expect(!MathExpression(text).isValid, "\(text)")
        #expect(MathExpression(text).evaluate(x: 1).isNaN, "\(text)")
    }
    #expect(MathTokeniser.tokenise("foo(x)").first == .unknown("foo"))
    #expect(MathExpression("sin x").isValid == false, "functions take brackets")
}

@Test func canonMathParse() {
    typealias Node = CanonMath.Node
    let x = Node.symbol("x")
    #expect(CanonMath.parse("x^2 - 4 = 0") == .relation("=", .sum([.power(x, .number("2")), .negate(.number("4"))]), .number("0")))
    #expect(CanonMath.parse("2x") == .product([.number("2"), x]) && CanonMath.parse("sin x") == .call("sin", [x]))
    #expect(CanonMath.parse("(x+1") == .sum([x, .number("1")]) && CanonMath.parse("x^") == .power(x, .hole))
    #expect(CanonMath.parse("x)") == nil && CanonMath.parse("  ") == nil)
}

@Test func canonMathPresent() {
    typealias Node = CanonMath.Node
    let x = Node.symbol("x")
    func present(_ text: String) -> Node? { CanonMath.parse(text).map(CanonMath.present) }
    #expect(present("b*c^(-1)") == .quotient(.symbol("b"), .symbol("c")))
    #expect(present("(1/2)*x^(-1/2)") == .quotient(.number("1"), .product([.number("2"), .call("sqrt", [x])])))
    #expect(present("-x^(-2)") == .negate(.quotient(.number("1"), .power(x, .number("2")))))
    #expect(present("1+3*x+x^2") == .sum([.power(x, .number("2")), .product([.number("3"), x]), .number("1")]))
    #expect(present("-b^2+a^2") == .sum([.power(.symbol("a"), .number("2")), .negate(.power(.symbol("b"), .number("2")))]))
    #expect(present("2*e^x*x") == .product([.number("2"), x, .power(.symbol("e"), x)]))
}
