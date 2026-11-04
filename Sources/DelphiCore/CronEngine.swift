import Foundation

// vixie cron semantics

public enum CronFieldKind: String, CaseIterable, Hashable, Sendable {
    case minute, hour, dom, month, dow
}

public struct CronFieldRule: Sendable {
    public let kind: CronFieldKind
    public let label: String
    public let min: Int
    public let max: Int
    public let rangeMax: Int
    public let names: [String: Int]?
}

public enum CronFieldShape: Equatable, Sendable {
    case star
    case step(Int)
    case single(Int)
    case range(lo: Int, hi: Int, step: Int)
    case set
}

public struct CronIssue: Error, Equatable, Sendable {
    public let text: String
    public let data: String?
}

public struct CronFieldParse: Sendable {
    public let source: String
    public let values: [Int]
    public let any: Bool
    public let shape: CronFieldShape?
    public let canon: String
    public let error: CronIssue?

    public var ok: Bool { error == nil }
}

public struct CronParse: Sendable {
    public let fields: [CronFieldParse]
    public let fieldCount: Int
    public let expression: String?

    public var ok: Bool { expression != nil }
}

public enum CronEngine {

    public static let monthNames: [String: Int] = [
        "jan": 1, "feb": 2, "mar": 3, "apr": 4, "may": 5, "jun": 6,
        "jul": 7, "aug": 8, "sep": 9, "oct": 10, "nov": 11, "dec": 12,
    ]

    public static let dowNames: [String: Int] = [
        "sun": 0, "mon": 1, "tue": 2, "wed": 3, "thu": 4, "fri": 5, "sat": 6,
    ]

    public static let monthLong = [
        "", "January", "February", "March", "April", "May", "June",
        "July", "August", "September", "October", "November", "December",
    ]

    public static let dowLong = [
        "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday",
    ]

    public static let fieldRules: [CronFieldRule] = [
        CronFieldRule(kind: .minute, label: String(localized: "Minute"), min: 0, max: 59, rangeMax: 59, names: nil),
        CronFieldRule(kind: .hour, label: String(localized: "Hour"), min: 0, max: 23, rangeMax: 23, names: nil),
        CronFieldRule(kind: .dom, label: String(localized: "Day of month"), min: 1, max: 31, rangeMax: 31, names: nil),
        CronFieldRule(kind: .month, label: String(localized: "Month"), min: 1, max: 12, rangeMax: 12, names: monthNames),
        CronFieldRule(kind: .dow, label: String(localized: "Day of week"), min: 0, max: 7, rangeMax: 6, names: dowNames),
    ]

    public static func rule(for kind: CronFieldKind) -> CronFieldRule {
        fieldRules.first { $0.kind == kind }!
    }

    private static func isDigits(_ token: String) -> Bool {
        !token.isEmpty && token.allSatisfy(\.isNumber) && token.allSatisfy(\.isASCII)
    }

    private static func isLetters(_ token: String) -> Bool {
        !token.isEmpty && token.allSatisfy { $0.isASCII && $0.isLetter }
    }

    private static func atom(_ token: String, _ rule: CronFieldRule) -> Result<Int, CronIssue> {
        if isDigits(token) {
            guard let n = Int(token) else {
                return .failure(CronIssue(text: String(localized: "Bad syntax"), data: token))
            }
            if n < rule.min || n > rule.max {
                return .failure(CronIssue(text: String(localized: "Out of range"),
                                          data: "\(token) (\(rule.min)–\(rule.max))"))
            }
            return .success(n)
        }
        if isLetters(token) {
            let lower = token.lowercased()
            if lower.count == 3, let hit = rule.names?[lower] { return .success(hit) }
            let other: [String: Int]? = rule.kind == .month ? dowNames
                : rule.kind == .dow ? monthNames : nil
            if lower.count == 3, other?[lower] != nil {
                return .failure(CronIssue(text: String(localized: "Wrong field"), data: token.uppercased()))
            }
            return .failure(CronIssue(text: String(localized: "Unknown name"), data: token.uppercased()))
        }
        return .failure(CronIssue(text: String(localized: "Bad syntax"), data: token))
    }

    private static func norm(_ rule: CronFieldRule, _ n: Int) -> Int {
        rule.kind == .dow && n == 7 ? 0 : n
    }

    private static func failed(_ source: String, _ issue: CronIssue) -> CronFieldParse {
        CronFieldParse(source: source, values: [], any: false, shape: nil, canon: "", error: issue)
    }

    public static func parseField(_ source: String, _ rule: CronFieldRule) -> CronFieldParse {
        let items = source.components(separatedBy: ",")
        var values = Set<Int>()
        var canonParts: [String] = []
        var canonSingles: [Int] = []
        var singleShape: CronFieldShape?
        var mixed = false

        for item in items {
            if item.isEmpty {
                return failed(source, CronIssue(text: String(localized: "Empty item"), data: source))
            }
            let slash = item.components(separatedBy: "/")
            if slash.count > 2 || slash[0].isEmpty {
                return failed(source, CronIssue(text: String(localized: "Bad syntax"), data: item))
            }
            let base = slash[0]
            var step = 1
            if slash.count == 2 {
                let stepToken = slash[1]
                guard isDigits(stepToken), let parsed = Int(stepToken), parsed != 0 else {
                    return failed(source, CronIssue(text: String(localized: "Bad step"), data: slash[1]))
                }
                step = parsed
            }

            let lo: Int
            let hi: Int
            var star = false
            var explicitRange = false

            if base == "*" {
                star = true
                lo = rule.min
                hi = rule.rangeMax
            } else if base.contains("-") {
                let seg = base.components(separatedBy: "-")
                if seg.count != 2 || seg[0].isEmpty || seg[1].isEmpty {
                    return failed(source, CronIssue(text: String(localized: "Bad syntax"), data: item))
                }
                let a: Int
                let b: Int
                switch atom(seg[0], rule) {
                case .failure(let issue): return failed(source, issue)
                case .success(let value): a = value
                }
                switch atom(seg[1], rule) {
                case .failure(let issue): return failed(source, issue)
                case .success(let value): b = value
                }
                if a > b {
                    return failed(source, CronIssue(text: String(localized: "Reversed range"), data: base.uppercased()))
                }
                lo = a
                hi = b
                explicitRange = true
            } else {
                switch atom(base, rule) {
                case .failure(let issue):
                    return failed(source, issue)
                case .success(let a):
                    lo = a
                    // vixie single-value step
                    hi = step > 1 ? rule.rangeMax : a
                }
            }

            // huge steps overflow
            for v in stride(from: lo, through: hi, by: min(step, rule.max + 1)) {
                values.insert(norm(rule, v))
            }

            if star {
                canonParts.append(step > 1 ? "*/\(step)" : "*")
            } else if explicitRange {
                canonParts.append(step > 1 ? "\(lo)-\(hi)/\(step)" : "\(lo)-\(hi)")
            } else if step > 1 {
                canonParts.append("\(lo)-\(rule.rangeMax)/\(step)")
            } else {
                let value = norm(rule, lo)
                if !canonSingles.contains(value) {
                    canonSingles.append(value)
                    canonParts.append(String(value))
                }
            }

            if items.count == 1 {
                if star && step == 1 {
                    singleShape = .star
                } else if star {
                    singleShape = .step(step)
                } else if explicitRange {
                    singleShape = .range(lo: lo, hi: hi, step: step)
                } else if step > 1 {
                    singleShape = .range(lo: lo, hi: rule.rangeMax, step: step)
                } else {
                    singleShape = .single(norm(rule, lo))
                }
            } else {
                mixed = true
            }
        }

        return CronFieldParse(
            source: source,
            values: values.sorted(),
            any: source == "*",
            shape: mixed ? .set : singleShape,
            canon: canonParts.joined(separator: ","),
            error: nil
        )
    }

    public static func parseCron(_ input: String) -> CronParse {
        let parts = input.split(whereSeparator: \.isWhitespace).map(String.init)
        guard parts.count == 5 else {
            return CronParse(fields: [], fieldCount: parts.count, expression: nil)
        }
        let fields = parts.enumerated().map { parseField($1, fieldRules[$0]) }
        guard fields.allSatisfy(\.ok) else {
            return CronParse(fields: fields, fieldCount: 5, expression: nil)
        }
        return CronParse(
            fields: fields,
            fieldCount: 5,
            expression: fields.map(\.canon).joined(separator: " ")
        )
    }

    private static func joinList(_ parts: [String]) -> String {
        if parts.count == 1 { return parts[0] }
        if parts.count == 2 { return "\(parts[0]) and \(parts[1])" }
        let tail = parts.dropLast().joined(separator: ", ")
        return "\(tail) and \(parts[parts.count - 1])"
    }

    private static func joinValues(_ values: [Int], _ name: ((Int) -> String)? = nil) -> String {
        let label = name ?? { String($0) }
        if values.count >= 2 {
            var contiguous = true
            for i in 1..<values.count where values[i] != values[i - 1] + 1 {
                contiguous = false
                break
            }
            if contiguous { return "\(label(values[0]))–\(label(values[values.count - 1]))" }
        }
        return joinList(values.map(label))
    }

    private static func hourClause(_ field: CronFieldParse) -> String {
        guard field.ok, !field.any, let s = field.shape else { return "" }
        switch s {
        case .single(let value):
            return "during hour \(value)"
        case .range(let lo, let hi, let step) where step > 1:
            return "every \(step) hours from \(lo) to \(hi)"
        case .range(let lo, let hi, _):
            return "during hours \(lo)–\(hi)"
        default:
            return "during hours \(joinValues(field.values))"
        }
    }

    private static func pad2(_ n: Int) -> String {
        n < 10 ? "0\(n)" : String(n)
    }

    private static func timeClause(_ minute: CronFieldParse, _ hour: CronFieldParse) -> String {
        guard minute.ok, let m = minute.shape else { return "" }
        let hourOk = hour.ok && !hour.any
        let hc = hourClause(hour)

        switch m {
        case .star:
            return hourOk ? "Every minute \(hc)" : "Every minute"
        case .step(let step):
            if step == 1 { return hourOk ? "Every minute \(hc)" : "Every minute" }
            return hourOk ? "Every \(step) minutes \(hc)" : "Every \(step) minutes"
        case .single(let value):
            if hour.ok, case .single(let h)? = hour.shape {
                return "At \(pad2(h)):\(pad2(value))"
            }
            return hourOk ? "At minute \(value) \(hc)" : "At minute \(value) past every hour"
        case .range(let lo, let hi, let step):
            let base = step > 1
                ? "Every \(step) minutes from \(lo) to \(hi)"
                : "Minutes \(lo)–\(hi)"
            return hourOk ? "\(base) \(hc)" : "\(base) past every hour"
        case .set:
            let base = "Minutes \(joinValues(minute.values))"
            return hourOk ? "\(base) \(hc)" : "\(base) past every hour"
        }
    }

    private static func domText(_ dom: CronFieldParse) -> String {
        guard dom.ok, !dom.any else { return "" }
        let suffix = dom.values.count == 1 ? "day" : "days"
        return "on \(suffix) \(joinValues(dom.values)) of the month"
    }

    private static func dowText(_ dow: CronFieldParse) -> String {
        guard dow.ok, !dow.any else { return "" }
        let values = dow.values
        if values.count == 5, values.enumerated().allSatisfy({ $1 == $0 + 1 }) {
            return "on weekdays"
        }
        if values.count == 2, values[0] == 0, values[1] == 6 { return "on weekends" }
        let single: (Int) -> String = { dowLong[$0] }
        if values.count == 1 { return "on \(single(values[0]))" }
        return "on \(joinList(values.map(single)))"
    }

    private static func monthText(_ month: CronFieldParse) -> String {
        guard month.ok, !month.any else { return "" }
        return "in \(joinValues(month.values) { monthLong[$0] })"
    }

    public static func describe(_ fields: [CronFieldParse]) -> String {
        guard fields.count == 5 else { return "" }
        var parts = [timeClause(fields[0], fields[1])]
        let domPart = domText(fields[2])
        let dowPart = dowText(fields[4])
        if !domPart.isEmpty && !dowPart.isEmpty {
            parts.append("\(domPart) or \(String(dowPart.dropFirst(3)))")
        } else if !domPart.isEmpty || !dowPart.isEmpty {
            parts.append(domPart.isEmpty ? dowPart : domPart)
        }
        let monthPart = monthText(fields[3])
        if !monthPart.isEmpty { parts.append(monthPart) }
        return parts.joined(separator: " ")
    }

    private static let maxScanDays = 366 * 5

    /// Cron fields are Gregorian; the default calendar is Gregorian in the current time zone.
    public static func nextRuns(fields: [CronFieldParse], count: Int, from: Date = Date(),
                         calendar: Calendar = Calendar(identifier: .gregorian)) -> [Date] {
        guard fields.count == 5, fields.allSatisfy(\.ok) else { return [] }
        let minutes = fields[0].values
        let hours = fields[1].values
        let domSet = Set(fields[2].values)
        let monthSet = Set(fields[3].values)
        let dowSet = Set(fields[4].values)
        let domAny = fields[2].any
        let dowAny = fields[4].any

        var out: [Date] = []
        var day = calendar.startOfDay(for: from)

        for _ in 0..<maxScanDays {
            if out.count >= count { break }
            let parts = calendar.dateComponents([.year, .month, .day, .weekday], from: day)
            guard let month = parts.month, let dayOfMonth = parts.day,
                  let weekday = parts.weekday else { break }

            if !monthSet.contains(month) {
                guard let firstOfMonth = calendar.date(from: DateComponents(
                    year: parts.year, month: month, day: 1)),
                      let nextMonth = calendar.date(byAdding: .month, value: 1, to: firstOfMonth)
                else { break }
                day = calendar.startOfDay(for: nextMonth)
                continue
            }

            let domHit = domAny || domSet.contains(dayOfMonth)
            let dowHit = dowAny || dowSet.contains(weekday - 1)
            // cron days use or
            let runsToday: Bool
            if domAny && dowAny { runsToday = true }
            else if domAny { runsToday = dowHit }
            else if dowAny { runsToday = domHit }
            else { runsToday = domHit || dowHit }

            if runsToday {
                for h in hours {
                    for m in minutes {
                        guard let t = calendar.date(from: DateComponents(
                            year: parts.year, month: month, day: dayOfMonth, hour: h, minute: m))
                        else { continue }
                        // dst gap times repeat
                        if t > out.last ?? from {
                            out.append(t)
                            if out.count == count { return out }
                        }
                    }
                }
            }

            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return out
    }

    #if DEBUG
    public static func selfCheck() {
        let weekly = parseCron("30 9 * * MON-FRI")
        assert(weekly.ok)
        assert(weekly.expression == "30 9 * * 1-5")
        assert(describe(weekly.fields) == "At 09:30 on weekdays")

        let every = parseCron("*/15 * * * *")
        assert(every.ok)
        assert(every.expression == "*/15 * * * *")
        assert(describe(every.fields) == "Every 15 minutes")
        assert(every.fields[0].values == [0, 15, 30, 45])

        assert(parseCron("* * * *").fieldCount == 4)
        assert(!parseCron("60 * * * *").ok)
        assert(parseField("5-1", rule(for: .hour)).error?.text == String(localized: "Reversed range"))
        assert(parseField("MON", rule(for: .month)).error?.text == String(localized: "Wrong field"))
        assert(parseField("*/0", rule(for: .minute)).error?.text == String(localized: "Bad step"))
        // dow 7 is sunday
        assert(parseField("7", rule(for: .dow)).values == [0])
        assert(parseField("5/10", rule(for: .minute)).values == [5, 15, 25, 35, 45, 55])

        let sunday = parseCron("0 0 1 1 0")
        assert(describe(sunday.fields)
               == "At 00:00 on day 1 of the month or Sunday in January")

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let start = calendar.date(from: DateComponents(
            year: 2026, month: 1, day: 1, hour: 0, minute: 0))!
        let runs = nextRuns(fields: every.fields, count: 3, from: start, calendar: calendar)
        assert(runs.count == 3)
        assert(calendar.component(.minute, from: runs[0]) == 15)
        assert(calendar.component(.minute, from: runs[2]) == 45)

        assert(parseField("59/9223372036854775807", rule(for: .minute)).values == [59])
        assert(parseField("*/9223372036854775807", rule(for: .minute)).canon == "*/9223372036854775807")
        assert(nextRuns(fields: parseCron("0 0 31 2 *").fields, count: 1, calendar: calendar).isEmpty)

        let leap = nextRuns(fields: parseCron("0 0 29 2 *").fields, count: 2,
                            from: start, calendar: calendar)
        assert(leap.map { calendar.component(.year, from: $0) } == [2028, 2032])

        // feb 2026 starts sunday
        let either = nextRuns(fields: parseCron("0 0 13 2 SUN").fields, count: 3,
                              from: start, calendar: calendar)
        assert(either.map { calendar.component(.day, from: $0) } == [1, 8, 13])

        // berlin dst gap 02:00
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        let beforeGap = calendar.date(from: DateComponents(year: 2026, month: 3, day: 29, hour: 1))!
        let gap = nextRuns(fields: parseCron("*/30 2,3 * * *").fields, count: 3,
                           from: beforeGap, calendar: calendar)
        assert(gap.map { calendar.component(.hour, from: $0) } == [3, 3, 2])
        assert(gap.map { calendar.component(.day, from: $0) } == [29, 29, 30])
    }
    #endif
}
