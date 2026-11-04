import CoreGraphics
import Foundation

/// Names for time zone identifiers.
public enum TimeCalcZones {
    /// UTC first, then round the world westwards from Honolulu.
    public static let common = [
        "UTC", "Pacific/Honolulu", "America/Anchorage", "America/Los_Angeles", "America/Denver", "America/Chicago",
        "America/New_York", "America/Sao_Paulo", "Atlantic/Reykjavik", "Europe/London", "Europe/Paris", "Europe/Berlin",
        "Europe/Moscow", "Africa/Cairo", "Asia/Dubai", "Asia/Kolkata", "Asia/Shanghai", "Asia/Tokyo", "Australia/Sydney",
        "Pacific/Auckland",
    ]

    public static let sorted: [String] = TimeZone.knownTimeZoneIdentifiers.sorted()

    /// Last part of the identifier, e.g. "Los Angeles".
    public static func city(_ zone: String) -> String {
        (zone.components(separatedBy: "/").last ?? zone).replacingOccurrences(of: "_", with: " ")
    }

    public static func abbreviation(_ zone: String, at date: Date) -> String {
        guard let time = TimeZone(identifier: zone) else { return "" }
        return time.abbreviation(for: date) ?? time.abbreviation() ?? ""
    }

    /// Offset from UTC as "UTC+5:30", "UTC−8" or "UTC".
    public static func offset(_ zone: String, at date: Date) -> String {
        guard let time = TimeZone(identifier: zone) else { return "" }
        let seconds = time.secondsFromGMT(for: date)
        return seconds == 0 ? "UTC" : "UTC" + signed(seconds)
    }

    /// Whole hours, or hours and minutes, with a true minus: "+9", "−3:30", "0".
    public static func signed(_ seconds: Int) -> String {
        guard seconds != 0 else { return "0" }
        let hours = abs(seconds) / 3600
        let minutes = abs(seconds) % 3600 / 60
        return (seconds < 0 ? "\u{2212}" : "+") + (minutes == 0 ? "\(hours)" : String(format: "%d:%02d", hours, minutes))
    }

    /// The zone's name in the user's language and its offset.
    public static func detail(_ zone: String, at date: Date) -> String {
        let name = TimeZone(identifier: zone)?.localizedName(for: .generic, locale: .current)
        return [name, offset(zone, at: date)].compactMap { $0 }.joined(separator: " \u{00B7} ")
    }

    /// "Berlin · CET", for result rows.
    public static func title(_ zone: String, at date: Date) -> String {
        city(zone) + " \u{00B7} " + abbreviation(zone, at: date)
    }
}

/// The world for the Timezone banner: land, cities to mark, and where the sun stands.
public enum TimeCalcWorld {
    /// Latitudes drawn: Antarctica's interior and the high Arctic have no cities to mark.
    public static let north = 80.0
    public static let south = -60.0
    /// Width over height of the map.
    public static let aspect = 360 / (north - south)

    /// Where a city of each common zone sits, as (lat, lon); the SwiftUI map's cities plus London and UTC's meridian.
    public static let places: [String: (Double, Double)] = [
        "Europe/Paris": (48.9, 2.3), "Europe/Berlin": (52.5, 13.4), "Europe/Moscow": (55.8, 37.6), "Europe/London": (51.5, -0.1),
        "Africa/Cairo": (30.0, 31.2), "Africa/Lagos": (6.5, 3.4), "Africa/Nairobi": (-1.3, 36.8),
        "Africa/Johannesburg": (-26.2, 28.0), "Africa/Casablanca": (33.6, -7.6), "Asia/Dubai": (25.3, 55.3),
        "Asia/Kolkata": (19.1, 72.9), "Asia/Singapore": (1.3, 103.8), "Asia/Shanghai": (39.9, 116.4), "Asia/Tokyo": (35.7, 139.7),
        "Australia/Sydney": (-33.9, 151.2), "Pacific/Auckland": (-36.8, 174.8), "America/New_York": (40.7, -74.0),
        "America/Chicago": (41.9, -87.6), "America/Denver": (39.7, -105.0), "America/Los_Angeles": (34.1, -118.2),
        "America/Anchorage": (61.2, -149.9), "Pacific/Honolulu": (21.3, -157.8), "America/Sao_Paulo": (-23.5, -46.6),
        "America/Argentina/Buenos_Aires": (-34.6, -58.4), "America/Lima": (-12.0, -77.0), "America/Bogota": (4.7, -74.1),
        "America/Santiago": (-33.4, -70.7), "Atlantic/Reykjavik": (64.1, -21.9), "UTC": (51.5, 0), "GMT": (51.5, 0),
    ]

    /// Natural Earth 110 m land rings as (lon, lat), one path in map units: x 0...360, y 0...(north - south).
    // immutable once built
    nonisolated(unsafe) public static let land: CGPath = {
        let path = CGMutablePath()
        guard let url = Bundle.module.url(forResource: "world-land", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let rings = try? JSONSerialization.jsonObject(with: data) as? [[[Double]]] else { return path }
        for ring in rings where ring.count > 2 {
            path.addLines(between: ring.compactMap { $0.count >= 2 ? CGPoint(x: $0[0] + 180, y: north - $0[1]) : nil })
            path.closeSubpath()
        }
        return path
    }()

    /// Where a place falls in `rect`, its latitude clamped to the latitudes drawn.
    public static func point(latitude: Double, longitude: Double, in rect: CGRect) -> CGPoint {
        let latitude = min(max(latitude, south), north)
        return CGPoint(x: rect.minX + CGFloat((longitude + 180) / 360) * rect.width, y: rect.minY + CGFloat((north - latitude) / (north - south)) * rect.height)
    }

    /// Lines every 30 degrees and the land, filled and outlined, over `rect` in `ink` at these opacities.
    public static func drawWorld(_ context: CGContext, in rect: CGRect, ink: CGColor, hairline: CGFloat, grid: CGFloat, land fill: CGFloat, coast: CGFloat) {
        context.setStrokeColor(ink.copy(alpha: grid) ?? ink)
        context.setLineWidth(hairline)
        for longitude in stride(from: -150.0, through: 150, by: 30) {
            let x = point(latitude: 0, longitude: longitude, in: rect).x
            context.strokeLineSegments(between: [CGPoint(x: x, y: rect.minY), CGPoint(x: x, y: rect.maxY)])
        }
        for latitude in stride(from: -30.0, through: 60, by: 30) {
            let y = point(latitude: latitude, longitude: 0, in: rect).y
            context.strokeLineSegments(between: [CGPoint(x: rect.minX, y: y), CGPoint(x: rect.maxX, y: y)])
        }
        var fit = CGAffineTransform(translationX: rect.minX, y: rect.minY).scaledBy(x: rect.width / 360, y: rect.height / CGFloat(north - south))
        guard let land = land.copy(using: &fit) else { return }
        context.addPath(land)
        context.setFillColor(ink.copy(alpha: fill) ?? ink)
        context.fillPath()
        context.addPath(land)
        context.setStrokeColor(ink.copy(alpha: coast) ?? ink)
        context.setLineWidth(0.5)
        context.strokePath()
    }

    /// The point on Earth with the sun overhead, as (lat, lon) in degrees: declination by day of year, longitude by UTC time.
    public static func subsolar(at date: Date) -> (Double, Double) {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let day = Double(utc.ordinality(of: .day, in: .year, for: date) ?? 1)
        let parts = utc.dateComponents([.hour, .minute, .second], from: date)
        let hours = Double(parts.hour ?? 0) + Double(parts.minute ?? 0) / 60 + Double(parts.second ?? 0) / 3600
        let declination = -23.44 * cos(2 * .pi / 365 * (day + 10))
        return (declination, -15 * (hours - 12))
    }

    /// Latitude of the day and night line at `lon`, for the sun over (`lat`, `lon`).
    public static func terminator(lon: Double, sun: (Double, Double)) -> Double {
        let declination = max(abs(sun.0), 0.1) * (sun.0 < 0 ? -1 : 1) * .pi / 180
        let angle = (lon - sun.1) * .pi / 180
        return atan(-cos(angle) / tan(declination)) * 180 / .pi
    }

    #if DEBUG
    public static func selfCheck() {
        // equinox noon: sun 0,0
        let noon = ISO8601DateFormatter().date(from: "2026-03-20T12:00:00Z")!
        let sun = subsolar(at: noon)
        assert(abs(sun.0) < 1.5 && abs(sun.1) < 0.01)
        // june: terminator near arctic
        let june = subsolar(at: ISO8601DateFormatter().date(from: "2026-06-21T12:00:00Z")!)
        assert(june.0 > 23 && abs(terminator(lon: 180, sun: june) - 66.6) < 1)
    }
    #endif
}

/// Calendar ticks for a time axis: a ladder of units from a minute to a million years.
public enum TimeCalcAxis {
    /// 2038-01-19 03:14:07 UTC, the last second a signed 32-bit count holds.
    public static let limit = Double(Int32.max)

    public struct Rung: Sendable {
        public let component: Calendar.Component
        public let count: Int
        /// Typical length, for choosing a rung.
        public let seconds: Double
        /// Rung of the finer ticks between these.
        public let minor: Int?
    }

    public static let rungs: [Rung] = {
        let minute = 60.0, hour = 3600.0, day = 86_400.0, month = 2_629_746.0, year = 31_556_952.0
        var rungs: [Rung] = [
            Rung(component: .minute, count: 1, seconds: minute, minor: nil),
            Rung(component: .minute, count: 5, seconds: 5 * minute, minor: 0),
            Rung(component: .minute, count: 15, seconds: 15 * minute, minor: 1),
            Rung(component: .minute, count: 30, seconds: 30 * minute, minor: 1),
            Rung(component: .hour, count: 1, seconds: hour, minor: 2),
            Rung(component: .hour, count: 3, seconds: 3 * hour, minor: 4),
            Rung(component: .hour, count: 6, seconds: 6 * hour, minor: 4),
            Rung(component: .hour, count: 12, seconds: 12 * hour, minor: 5),
            Rung(component: .day, count: 1, seconds: day, minor: 6),
            Rung(component: .day, count: 2, seconds: 2 * day, minor: 8),
            Rung(component: .weekOfYear, count: 1, seconds: 7 * day, minor: 8),
            Rung(component: .month, count: 1, seconds: month, minor: 8),
            Rung(component: .month, count: 3, seconds: 3 * month, minor: 11),
            Rung(component: .month, count: 6, seconds: 6 * month, minor: 11),
            Rung(component: .year, count: 1, seconds: year, minor: 11),
        ]
        // 1-2-5 years upwards
        var power = 1
        while power <= 100_000 {
            for mantissa in [2, 5, 10] where !(power == 100_000 && mantissa > 2) {
                let count = mantissa * power
                let finer = rungs.lastIndex { $0.component == .year && count / $0.count >= 5 } ?? 14
                rungs.append(Rung(component: .year, count: count, seconds: Double(count) * year, minor: finer))
            }
            power *= 10
        }
        return rungs
    }()

    /// Index of the finest rung whose ticks sit at least `gap` points apart.
    public static func rung(span: Double, width: Double, gap: Double) -> Int {
        guard span > 0, width > 0 else { return 0 }
        return rungs.firstIndex { $0.seconds / span * width >= gap } ?? rungs.count - 1
    }

    /// Ticks from `lo` to `hi`, counted from the start of the enclosing unit so they land on round values.
    public static func ticks(from lo: Date, to hi: Date, rung: Rung, calendar: Calendar) -> [Date] {
        let anchor: Date
        if rung.component == .year {
            let year = calendar.component(.year, from: lo)
            var parts = calendar.dateComponents([.era], from: lo)
            parts.year = Int((Double(year) / Double(rung.count)).rounded(.down)) * rung.count
            parts.month = 1
            parts.day = 1
            anchor = calendar.date(from: parts) ?? lo
        } else {
            let outer: Calendar.Component = switch rung.component {
            case .minute: .hour
            case .hour: .day
            case .day: .month
            case .weekOfYear: .weekOfYear
            default: .year
            }
            anchor = calendar.dateInterval(of: outer, for: lo)?.start ?? lo
        }
        var ticks: [Date] = []
        var step = 0
        while ticks.count < 400, step < 1000, let tick = calendar.date(byAdding: rung.component, value: step * rung.count, to: anchor), tick <= hi {
            if tick >= lo { ticks.append(tick) }
            step += 1
        }
        return ticks
    }

    /// Date template for a tick's label, and whether it opens a larger unit (a new day under hours, a new year under months).
    /// Day labels name the month on the first label and wherever the month changes after `previous`.
    public static func template(for tick: Date, after previous: Date?, rung: Rung, calendar: Calendar) -> (String, Bool) {
        switch rung.component {
        case .minute, .hour:
            calendar.startOfDay(for: tick) == tick ? ("MMMd", true) : ("jmm", false)
        case .day, .weekOfYear:
            previous.map { calendar.isDate($0, equalTo: tick, toGranularity: .month) } == true ? ("d", false) : ("MMMd", true)
        case .month:
            calendar.component(.month, from: tick) == 1 ? ("y", true) : ("MMM", false)
        default:
            ("y", false)
        }
    }

    #if DEBUG
    public static func selfCheck() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        // epoch-2038, 330 pt: decades
        let decades = rungs[rung(span: TimeCalcAxis.limit, width: 330, gap: 44)]
        assert(decades.component == .year && decades.count == 10)
        let years = ticks(from: Date(timeIntervalSince1970: 0), to: Date(timeIntervalSince1970: TimeCalcAxis.limit), rung: decades, calendar: calendar)
        assert(years.count == 7 && years.first == Date(timeIntervalSince1970: 0))
        // week, 330 pt: days
        let days = rungs[rung(span: 7 * 86_400, width: 330, gap: 44)]
        assert(days.component == .day && days.count == 1)
        let noon = Date(timeIntervalSince1970: 86_400 * 10 + 43_200)
        let hours = ticks(from: noon, to: noon.addingTimeInterval(86_400), rung: rungs[5], calendar: calendar)
        assert(hours.count == 9 && hours[0] == noon && template(for: hours[4], after: hours[3], rung: rungs[5], calendar: calendar).1)
        assert(rungs.allSatisfy { rung in rung.minor.map { rungs[$0].seconds < rung.seconds } ?? true })
        assert(TimeCalcZones.signed(19_800) == "+5:30" && TimeCalcZones.signed(-8 * 3600) == "\u{2212}8" && TimeCalcZones.signed(0) == "0")
    }
    #endif
}
