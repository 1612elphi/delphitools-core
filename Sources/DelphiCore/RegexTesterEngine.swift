import Foundation

public nonisolated enum RegexTesterEngine: Sendable {
    public struct Match: Sendable {
        public let range: NSRange
        /// One per capture group; nil for a group that took no part in the match.
        public let groups: [NSRange?]
    }

    public enum Outcome: Sendable {
        case empty
        case invalid(String)
        case timedOut
        case matched([Match], truncated: Bool, groups: Int)

        public var failed: Bool {
            switch self {
            case .invalid, .timedOut: true
            default: false
            }
        }
    }

    /// Flags as JavaScript writes them: g every match, i case insensitive, m line anchors, s dot matches newlines.
    /// Matching stops after `limit` matches, and gives up after `timeLimit` seconds (catastrophic backtracking).
    public static func run(pattern: String, flags: String, in text: String, limit: Int = 1000, timeLimit: Double = 0.4) -> Outcome {
        guard !pattern.isEmpty else { return .empty }
        var options: NSRegularExpression.Options = []
        if flags.contains("i") { options.insert(.caseInsensitive) }
        if flags.contains("m") { options.insert(.anchorsMatchLines) }
        if flags.contains("s") { options.insert(.dotMatchesLineSeparators) }
        let regex: NSRegularExpression
        do {
            regex = try NSRegularExpression(pattern: pattern, options: options)
        } catch {
            return .invalid(message(for: error))
        }
        let global = flags.contains("g")
        let start = CFAbsoluteTimeGetCurrent()
        var found: [Match] = []
        var truncated = false
        var timedOut = false
        // progress calls allow cancel
        regex.enumerateMatches(in: text, options: .reportProgress, range: NSRange(location: 0, length: (text as NSString).length)) { result, _, stop in
            if CFAbsoluteTimeGetCurrent() - start > timeLimit || Task.isCancelled {
                timedOut = true
                stop.pointee = true
                return
            }
            guard let result else { return }
            guard found.count < limit else {
                truncated = true
                stop.pointee = true
                return
            }
            let groups = (1..<max(1, result.numberOfRanges)).map { index -> NSRange? in
                let range = result.range(at: index)
                return range.location == NSNotFound ? nil : range
            }
            found.append(Match(range: result.range, groups: result.numberOfRanges > 1 ? groups : []))
            if !global { stop.pointee = true }
        }
        if timedOut { return .timedOut }
        return .matched(found, truncated: truncated, groups: regex.numberOfCaptureGroups)
    }

    /// ICU's reason, without the domain boilerplate.
    private static func message(for error: Error) -> String {
        let nsError = error as NSError
        let detail = nsError.userInfo["NSInvalidValue"] as? String
        return [String(localized: "Invalid pattern"), detail].compactMap { $0 }.joined(separator: " \u{00B7} ")
    }

    #if DEBUG
    public static func selfCheck() {
        let text = "ab ab ab"
        guard case .matched(let all, false, 1) = run(pattern: "(a)b", flags: "g", in: text) else { return assertionFailure("global") }
        assert(all.count == 3 && all[1].range == NSRange(location: 3, length: 2) && all[1].groups == [NSRange(location: 3, length: 1)])
        guard case .matched(let first, false, 0) = run(pattern: "ab", flags: "", in: text) else { return assertionFailure("first") }
        assert(first.count == 1)
        guard case .matched(let folded, _, _) = run(pattern: "AB", flags: "gi", in: text) else { return assertionFailure("case") }
        assert(folded.count == 3)
        guard case .matched(let optional, _, 2) = run(pattern: "(x)?(b)", flags: "g", in: "b") else { return assertionFailure("optional") }
        assert(optional.first?.groups.first == .some(nil))
        guard case .matched(let empty, _, _) = run(pattern: "^", flags: "gm", in: "a\nb") else { return assertionFailure("zero width") }
        assert(empty.count == 2 && empty.allSatisfy { $0.range.length == 0 })
        guard case .matched(let capped, true, _) = run(pattern: ".", flags: "g", in: String(repeating: "x", count: 20), limit: 5) else {
            return assertionFailure("limit")
        }
        assert(capped.count == 5)
        if case .invalid = run(pattern: "(", flags: "g", in: text) {} else { assertionFailure("invalid") }
        if case .empty = run(pattern: "", flags: "g", in: text) {} else { assertionFailure("empty") }
        let started = CFAbsoluteTimeGetCurrent()
        let runaway = run(pattern: "(a+)+$", flags: "g", in: String(repeating: "a", count: 40) + "b", timeLimit: 0.2)
        if case .timedOut = runaway {} else { assertionFailure("runaway not stopped") }
        assert(CFAbsoluteTimeGetCurrent() - started < 2, "runaway took too long to stop")
    }
    #endif
}
