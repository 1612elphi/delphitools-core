import Foundation

/// SMPTE timecode arithmetic, drop-frame included.
public enum Timecode: Sendable {

    public struct Parts: Equatable, Sendable {
        public var h: Int
        public var m: Int
        public var s: Int
        public var f: Int
        public var negative: Bool = false

        public init(h: Int, m: Int, s: Int, f: Int, negative: Bool = false) {
            (self.h, self.m, self.s, self.f, self.negative) = (h, m, s, f, negative)
        }
    }

    public struct Rate: Identifiable, Hashable, Sendable {
        public let id: String
        public let label: String
        public let nominal: Int
        public let exact: Double
        public let drop: Bool
    }

    public static let rates: [Rate] = [
        Rate(id: "23.976", label: "23.976", nominal: 24, exact: 24000.0 / 1001, drop: false),
        Rate(id: "24", label: "24", nominal: 24, exact: 24, drop: false),
        Rate(id: "25", label: "25", nominal: 25, exact: 25, drop: false),
        Rate(id: "29.97ndf", label: "29.97 NDF", nominal: 30, exact: 30000.0 / 1001, drop: false),
        Rate(id: "29.97df", label: "29.97 DF", nominal: 30, exact: 30000.0 / 1001, drop: true),
        Rate(id: "30", label: "30", nominal: 30, exact: 30, drop: false),
        Rate(id: "50", label: "50", nominal: 50, exact: 50, drop: false),
        Rate(id: "59.94ndf", label: "59.94 NDF", nominal: 60, exact: 60000.0 / 1001, drop: false),
        Rate(id: "59.94df", label: "59.94 DF", nominal: 60, exact: 60000.0 / 1001, drop: true),
        Rate(id: "60", label: "60", nominal: 60, exact: 60, drop: false),
    ]

    public static func rate(id: String) -> Rate {
        rates.first { $0.id == id } ?? rates[5]
    }

    private static func dropPerMinute(_ nominal: Int) -> Int {
        nominal >= 60 ? 4 : 2
    }

    /// Frame counts saturate here: about 385 days at 30 fps, and low enough that
    /// the conversions below cannot overflow on pasted or scripted input.
    public static let frameLimit = 1_000_000_000

    public static func frames(_ parts: Parts, rate: Rate) -> Int {
        let base = Double(rate.nominal)
        var frames = ((Double(parts.h) * 60 + Double(parts.m)) * 60 + Double(parts.s)) * base + Double(parts.f)
        if rate.drop {
            let dpm = Double(dropPerMinute(rate.nominal))
            let totalMinutes = (Double(parts.h) * 60 + Double(parts.m)).rounded(.down)
            frames -= dpm * (totalMinutes - (totalMinutes / 10).rounded(.down))
        }
        return clamp(parts.negative ? -frames : frames)
    }

    private static func clamp(_ frames: Double) -> Int {
        frames >= Double(frameLimit) ? frameLimit
            : frames <= Double(-frameLimit) ? -frameLimit
            : Int(frames)
    }

    public static func parts(frames frameNumber: Int, rate: Rate) -> Parts {
        let frameNumber = Swift.max(-frameLimit, Swift.min(frameLimit, frameNumber))
        let negative = frameNumber < 0
        var fn = abs(frameNumber)
        let base = rate.nominal

        if rate.drop {
            let dpm = dropPerMinute(base)
            let framesPer10Min = base * 60 * 10 - dpm * 9
            let framesPerMin = base * 60 - dpm
            let d = fn / framesPer10Min
            let mod = fn % framesPer10Min
            fn += mod >= dpm
                ? dpm * 9 * d + dpm * ((mod - dpm) / framesPerMin)
                : dpm * 9 * d
        }

        return Parts(
            h: fn / (base * 3600),
            m: (fn / (base * 60)) % 60,
            s: (fn / base) % 60,
            f: fn % base,
            negative: negative && frameNumber != 0
        )
    }

    public static func seconds(frames: Int, rate: Rate) -> Double {
        Double(frames) / rate.exact
    }

    public static func format(_ parts: Parts, rate: Rate) -> String {
        let sep = rate.drop ? ";" : ":"
        let sign = parts.negative ? "-" : ""
        return sign + [parts.h, parts.m, parts.s].map(pad).joined(separator: ":") + sep + pad(parts.f)
    }

    /// The standard rate nearest a track's frame rate; 29.97 and 59.94 count drop-frame, so the timecode follows the clock.
    public static func rate(fps: Double) -> Rate {
        guard fps.isFinite, fps > 0 else { return rate(id: "30") }
        let near = rates.filter { abs($0.exact - fps) < 0.01 }
        if let known = near.first(where: \.drop) ?? near.first { return known }
        return Rate(id: "custom", label: "", nominal: max(1, Int(fps.rounded())), exact: max(1, fps), drop: false)
    }

    /// SMPTE timecode of a playback position.
    public static func smpte(seconds: Double, rate: Rate) -> String {
        format(parts(frames: Int((max(0, seconds) * rate.exact + 1e-6).rounded(.down)), rate: rate), rate: rate)
    }

    public static func clock(seconds: Double) -> String {
        guard seconds.isFinite, Swift.abs(seconds) < 1e12 else { return "\u{2014}" }
        let sign = seconds < 0 ? "-" : ""
        let total = (Swift.abs(seconds) * 1000).rounded()
        let whole = Int(total / 1000)
        let ms = Int(total) - whole * 1000
        let parts = [whole / 3600, (whole / 60) % 60, whole % 60].map(pad).joined(separator: ":")
        return "\(sign)\(parts).\(String(format: "%03d", ms))"
    }

    private static func pad(_ n: Int) -> String {
        String(format: "%02d", n)
    }

    // MARK: - Parsing

    public enum ParseError: Equatable, Sendable {
        case empty
        case tooMany
        case notNumeric
        case frameRange(max: Int)
        case secondsRange
        case minutesRange
    }

    public enum ParseResult: Equatable, Sendable {
        case ok(parts: Parts, frames: Int, snappedFrom: String?)
        case failed(ParseError)
    }

    public static func parse(_ input: String, rate: Rate) -> ParseResult {
        let raw = input.trimmingCharacters(in: .whitespaces)
        if raw.isEmpty { return .failed(.empty) }

        let negative = raw.hasPrefix("-")
        let body = negative ? String(raw.dropFirst()).trimmingCharacters(in: .whitespaces) : raw

        let tokens = body
            .split(separator: ":", omittingEmptySubsequences: false)
            .flatMap { $0.split(separator: ";", omittingEmptySubsequences: false) }
            .flatMap { $0.split(separator: ".", omittingEmptySubsequences: false) }
            .flatMap { $0.split(separator: ",", omittingEmptySubsequences: false) }
            .map { $0.trimmingCharacters(in: .whitespaces) }

        if tokens.count > 4 { return .failed(.tooMany) }
        let nums = tokens.compactMap { token in
            token.allSatisfy { $0.isASCII && $0.isNumber } ? Int(token) : nil
        }
        if nums.count != tokens.count || nums.isEmpty { return .failed(.notNumeric) }

        // right-align parsed fields
        var padded = [0, 0, 0, 0]
        for (i, n) in nums.enumerated() { padded[4 - nums.count + i] = n }
        let (h, m, s, f) = (padded[0], padded[1], padded[2], padded[3])

        if f >= rate.nominal { return .failed(.frameRange(max: rate.nominal - 1)) }
        if s > 59 { return .failed(.secondsRange) }
        if m > 59 { return .failed(.minutesRange) }

        var parts = Parts(h: h, m: m, s: s, f: f, negative: negative)
        var snappedFrom: String?

        // skip invalid drop-frame numbers
        if rate.drop {
            let dpm = dropPerMinute(rate.nominal)
            if m % 10 != 0 && s == 0 && f < dpm {
                snappedFrom = format(Parts(h: h, m: m, s: s, f: f), rate: rate)
                parts.f = dpm
            }
        }

        return .ok(parts: parts, frames: frames(parts, rate: rate), snappedFrom: snappedFrom)
    }
}

#if DEBUG
extension Timecode {
    public static func selfCheck() {
        assert(rate(fps: 29.97).id == "29.97df" && rate(fps: 30).id == "30" && rate(fps: 23.976).id == "23.976" && rate(fps: 12).nominal == 12)
        assert(smpte(seconds: 1.5, rate: rate(fps: 25)) == "00:00:01:12" && smpte(seconds: 0, rate: rate(fps: 29.97)) == "00:00:00;00")
        let df30 = rate(id: "29.97df")
        let ndf25 = rate(id: "25")
        let df60 = rate(id: "59.94df")

        assert(frames(Parts(h: 1, m: 0, s: 0, f: 0), rate: df30) == 107892)
        assert(parts(frames: 107892, rate: df30) == Parts(h: 1, m: 0, s: 0, f: 0))
        assert(frames(Parts(h: 0, m: 1, s: 0, f: 2), rate: df30) == 1800)
        assert(format(parts(frames: 1800, rate: df30), rate: df30) == "00:01:00;02")
        assert(frames(Parts(h: 1, m: 0, s: 0, f: 0), rate: df60) == 215784)
        assert(parts(frames: 215784, rate: df60) == Parts(h: 1, m: 0, s: 0, f: 0))

        // the tenth minute keeps ;00
        assert(frames(Parts(h: 0, m: 10, s: 0, f: 0), rate: df30) == 17982)
        assert(format(parts(frames: 17982, rate: df30), rate: df30) == "00:10:00;00")
        guard case .ok(_, let before, _) = parse("00:00:59;29", rate: df30) else { return assertionFailure() }
        assert(format(parts(frames: before + 1, rate: df30), rate: df30) == "00:01:00;02")
        assert(frames(parts(frames: -1800, rate: df30), rate: df30) == -1800)

        for rate in [df30, df60, ndf25] {
            let limit = Int((rate.exact * 1200).rounded())
            for frame in 0...limit where frames(parts(frames: frame, rate: rate), rate: rate) != frame {
                return assertionFailure("\(rate.id) breaks at \(frame)")
            }
        }

        // pasted nonsense saturates
        assert(frames(Parts(h: .max, m: .max, s: .max, f: .max), rate: df30) == frameLimit)
        assert(parts(frames: .min, rate: df30).negative)
        assert(clock(seconds: 1.9999) == "00:00:02.000")
        assert(clock(seconds: .infinity) == "\u{2014}")

        assert(frames(Parts(h: 0, m: 0, s: 10, f: 12), rate: ndf25) == 262)
        assert(format(parts(frames: -262, rate: ndf25), rate: ndf25) == "-00:00:10:12")

        guard case .ok(_, let f1, _) = parse("10:12", rate: ndf25) else { return assertionFailure() }
        assert(f1 == 262)
        guard case .ok(let p2, _, let snapped) = parse("00:01:00;00", rate: df30) else { return assertionFailure() }
        assert(snapped == "00:01:00;00" && p2.f == 2)
        guard case .ok(_, _, let none) = parse("00:10:00;00", rate: df30) else { return assertionFailure() }
        assert(none == nil)
        assert(parse("", rate: ndf25) == .failed(.empty))
        assert(parse("1:2:3:4:5", rate: ndf25) == .failed(.tooMany))
        assert(parse("ab:cd", rate: ndf25) == .failed(.notNumeric))
        assert(parse("00:00:00:25", rate: ndf25) == .failed(.frameRange(max: 24)))
        assert(parse("00:00:60:00", rate: ndf25) == .failed(.secondsRange))
        assert(parse("00:60:00:00", rate: ndf25) == .failed(.minutesRange))

        assert(clock(seconds: 3661.5) == "01:01:01.500")
        assert(clock(seconds: -1.25) == "-00:00:01.250")
    }
}
#endif
