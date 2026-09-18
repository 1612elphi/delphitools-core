import Foundation

/// Parses `<number> <unit>` and `<number> <unit> to <unit>` and converts through Foundation's `Dimension` units.
public enum UnitConversion {
    public struct Answer: Equatable, Sendable {
        public let value: Double
        public let symbol: String

        /// Six significant digits, `.` as the decimal separator in every locale.
        public var text: String {
            value.formatted(.number.precision(.significantDigits(1...6)).grouping(.never).locale(Locale(identifier: "en_US_POSIX")))
                + " " + symbol
        }
    }

    /// With a target unit: one answer. Without: the first three other units of the same dimension, in table order.
    public static func answers(_ input: String) -> [Answer] {
        guard let match = input.trimmingCharacters(in: .whitespaces).lowercased().wholeMatch(of: shape),
              let number = Double(match.1.replacingOccurrences(of: ",", with: ".")),
              let source = unit(String(match.2))
        else { return [] }
        let measurement = Measurement(value: number, unit: source)
        let family = units.map(\.unit).filter { same($0, source) }
        let targets: [Dimension]
        if let name = match.3 {
            guard let target = unit(String(name)), same(target, source) else { return [] }
            targets = [target]
        } else {
            targets = Array(family.filter { $0 != source }.prefix(3))
        }
        return targets.map { Answer(value: convert(measurement, to: $0), symbol: $0.symbol) }
    }

    /// Every accepted spelling, grouped by dimension in table order.
    public static var catalogue: [(dimension: String, names: [String])] {
        var groups: [(dimension: String, names: [String])] = []
        for entry in units {
            let dimension = dimensionName(entry.unit)
            if groups.last?.dimension == dimension {
                groups[groups.count - 1].names += entry.names
            } else {
                groups.append((dimension, entry.names))
            }
        }
        return groups
    }

    private static func dimensionName(_ unit: Dimension) -> String {
        switch unit {
        case is UnitLength: "Length"
        case is UnitMass: "Mass"
        case is UnitTemperature: "Temperature"
        case is UnitVolume: "Volume"
        case is UnitArea: "Area"
        case is UnitSpeed: "Speed"
        case is UnitDuration: "Duration"
        case is UnitInformationStorage: "Storage"
        case is UnitAngle: "Angle"
        case is UnitPressure: "Pressure"
        case is UnitEnergy: "Energy"
        case is UnitPower: "Power"
        case is UnitFrequency: "Frequency"
        default: String(describing: type(of: unit))
        }
    }

    // comma decimals, lazy unit
    nonisolated(unsafe) private static let shape = /(-?\d+(?:[.,]\d+)?)\s*([^\d\s].*?)(?:\s+(?:to|in|as)\s+(.+))?/

    // dynamic types differ (measured)
    private static func same(_ a: Dimension, _ b: Dimension) -> Bool {
        type(of: a).baseUnit() == type(of: b).baseUnit()
    }

    private static func unit(_ name: String) -> Dimension? {
        let key = name.replacingOccurrences(of: " ", with: "")
        return units.first { $0.names.contains(key) }?.unit
    }

    // base unit bridges dimensions
    private static func convert(_ measurement: Measurement<Dimension>, to target: Dimension) -> Double {
        target.converter.value(fromBaseUnitValue: measurement.unit.converter.baseUnitValue(fromValue: measurement.value))
    }

    private static func length(_ symbol: String, metres: Double) -> UnitLength {
        UnitLength(symbol: symbol, converter: UnitConverterLinear(coefficient: metres))
    }

    // css units per inch
    private static let inch = 0.0254
    private static let day = UnitDuration(symbol: "d", converter: UnitConverterLinear(coefficient: 86400))
    private static let week = UnitDuration(symbol: "wk", converter: UnitConverterLinear(coefficient: 604_800))

    // first three, first match
    private static let units: [(names: [String], unit: Dimension)] = [
        (["mm", "millimetre", "millimetres", "millimeter", "millimeters"], UnitLength.millimeters),
        (["in", "inch", "inches", "\""], UnitLength.inches),
        (["cm", "centimetre", "centimetres", "centimeter", "centimeters"], UnitLength.centimeters),
        (["m", "metre", "metres", "meter", "meters"], UnitLength.meters),
        (["km", "kilometre", "kilometres", "kilometer", "kilometers"], UnitLength.kilometers),
        (["ft", "foot", "feet", "'"], UnitLength.feet),
        (["yd", "yard", "yards"], UnitLength.yards),
        (["mi", "mile", "miles"], UnitLength.miles),
        (["nmi", "nauticalmile", "nauticalmiles"], UnitLength.nauticalMiles),
        (["px"], length("px", metres: inch / 96)),
        (["pt", "point", "points"], length("pt", metres: inch / 72)),
        (["pc", "pica", "picas"], length("pc", metres: inch / 6)),
        (["rem"], length("rem", metres: 16 * inch / 96)),
        (["em"], length("em", metres: 16 * inch / 96)),

        (["kg", "kilogram", "kilograms", "kilo", "kilos"], UnitMass.kilograms),
        (["lb", "lbs", "pound", "pounds"], UnitMass.pounds),
        (["g", "gram", "grams"], UnitMass.grams),
        (["oz", "ounce", "ounces"], UnitMass.ounces),
        (["mg", "milligram", "milligrams"], UnitMass.milligrams),
        (["st", "stone"], UnitMass.stones),
        (["t", "tonne", "tonnes"], UnitMass.metricTons),

        (["c", "°c", "celsius"], UnitTemperature.celsius),
        (["f", "°f", "fahrenheit"], UnitTemperature.fahrenheit),
        (["k", "kelvin"], UnitTemperature.kelvin),

        (["l", "litre", "litres", "liter", "liters"], UnitVolume.liters),
        (["ml", "millilitre", "millilitres", "milliliter", "milliliters"], UnitVolume.milliliters),
        (["cup", "cups"], UnitVolume.cups),
        (["floz", "fluidounce", "fluidounces"], UnitVolume.fluidOunces),
        (["tbsp", "tablespoon", "tablespoons"], UnitVolume.tablespoons),
        (["tsp", "teaspoon", "teaspoons"], UnitVolume.teaspoons),
        (["pint", "pints"], UnitVolume.pints),
        (["gal", "gallon", "gallons"], UnitVolume.gallons),
        (["cl"], UnitVolume.centiliters),
        (["dl"], UnitVolume.deciliters),
        (["m3", "m³"], UnitVolume.cubicMeters),

        (["m2", "m²", "sqm"], UnitArea.squareMeters),
        (["ft2", "ft²", "sqft"], UnitArea.squareFeet),
        (["ha", "hectare", "hectares"], UnitArea.hectares),
        (["ac", "acre", "acres"], UnitArea.acres),
        (["km2", "km²", "sqkm"], UnitArea.squareKilometers),
        (["cm2", "cm²"], UnitArea.squareCentimeters),
        (["mm2", "mm²"], UnitArea.squareMillimeters),
        (["in2", "in²", "sqin"], UnitArea.squareInches),
        (["mi2", "mi²", "sqmi"], UnitArea.squareMiles),

        (["km/h", "kmh", "kph"], UnitSpeed.kilometersPerHour),
        (["mph"], UnitSpeed.milesPerHour),
        (["m/s"], UnitSpeed.metersPerSecond),
        (["kn", "kt", "knot", "knots"], UnitSpeed.knots),

        (["s", "sec", "secs", "second", "seconds"], UnitDuration.seconds),
        (["min", "mins", "minute", "minutes"], UnitDuration.minutes),
        (["h", "hr", "hrs", "hour", "hours"], UnitDuration.hours),
        (["d", "day", "days"], day),
        (["wk", "week", "weeks"], week),
        (["ms", "millisecond", "milliseconds"], UnitDuration.milliseconds),

        (["mb", "megabyte", "megabytes"], UnitInformationStorage.megabytes),
        (["gb", "gigabyte", "gigabytes"], UnitInformationStorage.gigabytes),
        (["kb", "kilobyte", "kilobytes"], UnitInformationStorage.kilobytes),
        (["b", "byte", "bytes"], UnitInformationStorage.bytes),
        (["tb", "terabyte", "terabytes"], UnitInformationStorage.terabytes),
        (["kib"], UnitInformationStorage.kibibytes),
        (["mib"], UnitInformationStorage.mebibytes),
        (["gib"], UnitInformationStorage.gibibytes),
        (["tib"], UnitInformationStorage.tebibytes),
        (["bit", "bits"], UnitInformationStorage.bits),

        (["deg", "°", "degree", "degrees"], UnitAngle.degrees),
        (["rad", "radian", "radians"], UnitAngle.radians),
        (["grad", "gradian", "gradians"], UnitAngle.gradians),
        (["turn", "turns", "rev"], UnitAngle.revolutions),

        (["bar"], UnitPressure.bars),
        (["psi"], UnitPressure.poundsForcePerSquareInch),
        (["kpa"], UnitPressure.kilopascals),
        (["hpa", "mbar"], UnitPressure.hectopascals),
        (["mmhg"], UnitPressure.millimetersOfMercury),

        (["kwh"], UnitEnergy.kilowattHours),
        (["kj"], UnitEnergy.kilojoules),
        (["kcal"], UnitEnergy.kilocalories),
        (["j", "joule", "joules"], UnitEnergy.joules),
        (["cal"], UnitEnergy.calories),

        (["w", "watt", "watts"], UnitPower.watts),
        (["kw", "kilowatt", "kilowatts"], UnitPower.kilowatts),
        (["hp", "horsepower"], UnitPower.horsepower),

        (["hz"], UnitFrequency.hertz),
        (["khz"], UnitFrequency.kilohertz),
        (["mhz"], UnitFrequency.megahertz),
        (["ghz"], UnitFrequency.gigahertz),
    ]
}
