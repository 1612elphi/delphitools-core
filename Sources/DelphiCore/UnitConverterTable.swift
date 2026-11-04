import Foundation

/// Graduation steps shared by the scale pictures: unit converter, type gauges.
public enum TickScale {
    /// Smallest of 1, 2, 5 times a power of ten that is at least `minimum`.
    public static func niceStep(atLeast minimum: Double) -> Double {
        guard minimum > 0, minimum.isFinite else { return 1 }
        let power = pow(10, floor(log10(minimum)))
        for mantissa in [1.0, 2, 5, 10] where mantissa * power >= minimum * (1 - 1e-9) {
            return mantissa * power
        }
        return 10 * power
    }

    /// Minor ticks per major: fifths of 1 and 5, quarters of 2.
    public static func subdivisions(of major: Double) -> Double {
        let mantissa = (major / pow(10, floor(log10(major)))).rounded()
        return mantissa == 2 ? 4 : 5
    }

    /// At most four decimals, trailing zeros dropped: 0.5, 0.6875, 26.25.
    public static func decimal(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...4)).grouping(.never).locale(Locale(identifier: "en_US_POSIX")))
    }
}

public enum UnitConverterTable {
    public static let categories = ["Length", "Weight", "Temperature", "Data", "Speed", "Volume", "Area", "Time", "Pressure"]

    /// The pair a category opens on, by unit id.
    public static let pairs: [String: (from: String, to: String)] = [
        "Length": ("km", "mi"), "Weight": ("kg", "lb"), "Temperature": ("C", "F"), "Data": ("GB", "MB"), "Speed": ("km/h", "mph"),
        "Volume": ("L", "gal"), "Area": ("m\u{00B2}", "ft\u{00B2}"), "Time": ("hr", "min"), "Pressure": ("bar", "psi"),
    ]

    public struct Entry: Sendable {
        public let id: String
        public let label: String
        public let dimension: Dimension

        public init(id: String, label: String, dimension: Dimension) {
            (self.id, self.label, self.dimension) = (id, label, dimension)
        }
    }

    public static func units(_ category: String) -> [Entry] {
        let entry = Entry.init
        switch category {
        case "Length":
            return [
                entry("m", "Metres", UnitLength.meters), entry("km", "Kilometres", UnitLength.kilometers),
                entry("cm", "Centimetres", UnitLength.centimeters), entry("mm", "Millimetres", UnitLength.millimeters),
                entry("mi", "Miles", UnitLength.miles), entry("yd", "Yards", UnitLength.yards),
                entry("ft", "Feet", UnitLength.feet), entry("in", "Inches", UnitLength.inches),
            ]
        case "Weight":
            return [
                entry("kg", "Kilograms", UnitMass.kilograms), entry("g", "Grams", UnitMass.grams),
                entry("mg", "Milligrams", UnitMass.milligrams), entry("lb", "Pounds", UnitMass.pounds),
                entry("oz", "Ounces", UnitMass.ounces), entry("st", "Stones", UnitMass.stones),
                entry("t", "Tonnes", UnitMass.metricTons),
            ]
        case "Temperature":
            return [
                entry("C", "Celsius", UnitTemperature.celsius), entry("F", "Fahrenheit", UnitTemperature.fahrenheit),
                entry("K", "Kelvin", UnitTemperature.kelvin),
            ]
        case "Data":
            return [
                entry("B", "Bytes", UnitInformationStorage.bytes), entry("KB", "Kilobytes", UnitInformationStorage.kilobytes),
                entry("MB", "Megabytes", UnitInformationStorage.megabytes), entry("GB", "Gigabytes", UnitInformationStorage.gigabytes),
                entry("TB", "Terabytes", UnitInformationStorage.terabytes), entry("bit", "Bits", UnitInformationStorage.bits),
                entry("Kbit", "Kilobits", UnitInformationStorage.kilobits), entry("Mbit", "Megabits", UnitInformationStorage.megabits),
            ]
        case "Speed":
            return [
                entry("m/s", "Metres/sec", UnitSpeed.metersPerSecond), entry("km/h", "Kilometres/hr", UnitSpeed.kilometersPerHour),
                entry("mph", "Miles/hr", UnitSpeed.milesPerHour), entry("kn", "Knots", UnitSpeed.knots),
            ]
        case "Volume":
            return [
                entry("L", "Litres", UnitVolume.liters), entry("mL", "Millilitres", UnitVolume.milliliters),
                entry("gal", "Gallons (US)", UnitVolume.gallons), entry("qt", "Quarts (US)", UnitVolume.quarts),
                entry("pt", "Pints (US)", UnitVolume.pints), entry("cup", "Cups (US)", UnitVolume.cups),
                entry("fl oz", "Fluid Ounces (US)", UnitVolume.fluidOunces), entry("tbsp", "Tablespoons", UnitVolume.tablespoons),
                entry("tsp", "Teaspoons", UnitVolume.teaspoons),
            ]
        case "Area":
            return [
                entry("m\u{00B2}", "Square Metres", UnitArea.squareMeters), entry("km\u{00B2}", "Square Kilometres", UnitArea.squareKilometers),
                entry("ft\u{00B2}", "Square Feet", UnitArea.squareFeet), entry("mi\u{00B2}", "Square Miles", UnitArea.squareMiles),
                entry("ha", "Hectares", UnitArea.hectares), entry("ac", "Acres", UnitArea.acres),
            ]
        case "Time":
            return [
                entry("s", "Seconds", UnitDuration.seconds), entry("ms", "Milliseconds", UnitDuration.milliseconds),
                entry("min", "Minutes", UnitDuration.minutes), entry("hr", "Hours", UnitDuration.hours),
            ]
        case "Pressure":
            return [
                entry("Pa", "Pascals", UnitPressure.newtonsPerMetersSquared), entry("hPa", "Hectopascals", UnitPressure.hectopascals),
                entry("bar", "Bars", UnitPressure.bars), entry("mbar", "Millibars", UnitPressure.millibars),
                entry("psi", "PSI", UnitPressure.poundsForcePerSquareInch), entry("inHg", "Inches of Mercury", UnitPressure.inchesOfMercury),
                entry("mmHg", "mmHg", UnitPressure.millimetersOfMercury),
            ]
        default:
            return []
        }
    }

    /// A unit as a scale: its dimension and the symbol printed on it.
    public struct Scale: Sendable {
        public let unit: Dimension
        public let symbol: String

        public init(_ entry: Entry) {
            unit = entry.dimension
            symbol = Self.symbol(entry.id)
        }

        public init(unit: Dimension, symbol: String) {
            self.unit = unit
            self.symbol = symbol
        }

        public static func symbol(_ id: String) -> String {
            switch id {
            case "C": "°C"
            case "F": "°F"
            default: id
            }
        }

        public func base(_ value: Double) -> Double { unit.converter.baseUnitValue(fromValue: value) }
        public func value(_ base: Double) -> Double { unit.converter.value(fromBaseUnitValue: base) }
    }

    /// Up to four decimals; a value that needs more, and one from a billion up, is a mantissa times a power of ten.
    public static func format(_ value: Double) -> String {
        guard value.isFinite else { return "\u{2014}" }
        let magnitude = abs(value)
        if magnitude == 0 { return "0" }
        let decimal = TickScale.decimal(value)
        // 0.00062 would lose digits
        if magnitude < 1e9, magnitude >= 0.01 || magnitude >= 1e-4 && abs((Double(decimal) ?? 0) - value) <= magnitude * 1e-9 { return decimal }
        var exponent = Int(log10(magnitude).rounded(.down))
        var mantissa = value / pow(10, Double(exponent))
        // 9.99996 rounds to 10
        if abs((mantissa * 1e4).rounded()) >= 1e5 {
            mantissa /= 10
            exponent += 1
        }
        let digits = String(exponent).map { character -> Character in
            character == "-" ? "\u{207B}" : Array("⁰¹²³⁴⁵⁶⁷⁸⁹")[Int(String(character)) ?? 0]
        }
        return TickScale.decimal(mantissa) + "×10" + String(digits)
    }

    /// The right side of `to = from × m + c`, or of `to = (from − a) ÷ k` when the slope is below one: the forms printed on conversion charts.
    public static func formula(from: Scale, to: Scale) -> String {
        let offset = to.value(from.base(0))
        let slope = to.value(from.base(1)) - offset
        let number = { (value: Double) in TickScale.decimal(abs(value)) }
        let signed = { (value: Double) in value < 0 ? " \u{2212} " + number(value) : " + " + number(value) }
        let shows = { (value: Double) in abs(value) >= 0.00005 }
        if abs(slope) >= 1 - 1e-9 {
            let scaled = abs(slope - 1) < 1e-9 ? from.symbol : from.symbol + " × " + number(slope)
            return scaled + (shows(offset) ? signed(offset) : "")
        }
        let shift = -offset / slope
        let inner = shows(shift) ? "(" + from.symbol + signed(-shift) + ")" : from.symbol
        return inner + " ÷ " + number(1 / slope)
    }

    /// Scale numbers: plain decimals from 0.0001 up to ten million, which are shorter there than a power of ten.
    public static func tickLabel(_ value: Double) -> String {
        let magnitude = abs(value)
        guard magnitude == 0 || (1e-4..<1e7).contains(magnitude) else { return format(value) }
        return (value + 0).formatted(.number.precision(.significantDigits(1...6)).grouping(.never).locale(Locale(identifier: "en_US_POSIX")))
    }

    #if DEBUG
    public static func selfCheck() {
        assert(TickScale.niceStep(atLeast: 0.9) == 1 && TickScale.niceStep(atLeast: 1.5) == 2 && TickScale.niceStep(atLeast: 30) == 50)
        assert(TickScale.subdivisions(of: 20) == 4 && TickScale.subdivisions(of: 50) == 5)
        assert(TickScale.decimal(0.5) == "0.5" && TickScale.decimal(1.0 / 3) == "0.3333" && TickScale.decimal(1234.5) == "1234.5")
        assert(format(0.6214) == "0.6214" && format(1) == "1" && format(0) == "0" && format(-40) == "-40")
        assert(format(0.001) == "0.001" && format(0.00062) == "6.2×10⁻⁴" && format(6.2137e-7) == "6.2137×10⁻⁷" && format(1.5e12) == "1.5×10¹²")
        assert(format(9.99999e-5) == "1×10⁻⁴")
        assert(tickLabel(0.001) == "0.001" && tickLabel(2_000_000) == "2000000" && tickLabel(-0.0) == "0" && tickLabel(3e12) == "3×10¹²")
        let celsius = Scale(unit: UnitTemperature.celsius, symbol: "°C"), fahrenheit = Scale(unit: UnitTemperature.fahrenheit, symbol: "°F")
        let kelvin = Scale(unit: UnitTemperature.kelvin, symbol: "K")
        assert(formula(from: celsius, to: fahrenheit) == "°C × 1.8 + 32")
        assert(formula(from: fahrenheit, to: celsius) == "(°F \u{2212} 32) ÷ 1.8")
        assert(formula(from: celsius, to: kelvin) == "°C + 273.15" && formula(from: kelvin, to: celsius) == "K \u{2212} 273.15")
        for category in categories {
            let ids = units(category).map(\.id)
            assert(ids.count >= 3 && Set(ids).count == ids.count, category)
            assert(pairs[category].map { ids.contains($0.from) && ids.contains($0.to) } ?? false, category)
        }
    }
    #endif
}
