import Foundation

/// One class of the cheat sheet: the class, the CSS it sets, and an example for a prefix.
public struct TailwindClass: Hashable, Sendable {
    public let name: String
    public let css: String
    public let example: String?
}

public struct TailwindCategory: Sendable {
    public let name: String
    public let items: [TailwindClass]

    /// The heading as shown; the data keeps the web's English names.
    public var title: String { Self.titles[name] ?? name }

    private static let titles: [String: String] = [
        "Breakpoints": String(localized: "Breakpoints"),
        "Display": String(localized: "Display"),
        "Position": String(localized: "Position"),
        "Flexbox": String(localized: "Flexbox"),
        "Grid": String(localized: "Grid"),
        "Alignment": String(localized: "Alignment"),
        "Spacing": String(localized: "Spacing"),
        "Sizing": String(localized: "Sizing"),
        "Typography": String(localized: "Typography"),
        "Text": String(localized: "Text"),
        "Backgrounds": String(localized: "Backgrounds"),
        "Borders": String(localized: "Borders"),
        "Effects": String(localized: "Effects"),
        "Transitions": String(localized: "Transitions"),
        "Transforms": String(localized: "Transforms"),
        "Interactivity": String(localized: "Interactivity"),
        "States": String(localized: "States"),
        "Overflow & Z-Index": String(localized: "Overflow & Z-Index"),
        "Arbitrary Values": String(localized: "Arbitrary Values"),
    ]
}

/// The web tool's table (`tailwind-cheatsheet.gts`), plus its square-bracket tip as a last category.
public enum TailwindCheatsheet: Sendable {
    public nonisolated static let categories: [TailwindCategory] = {
        guard let url = Bundle.module.url(forResource: "tailwind-cheatsheet", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let raw = try? JSONDecoder().decode([Raw].self, from: data) else { return [] }
        return raw.map { category in
            TailwindCategory(name: category.name, items: category.items.compactMap { row in
                row.count >= 2 ? TailwindClass(name: row[0], css: row[1], example: row.count > 2 ? row[2] : nil) : nil
            })
        }
    }()

    private nonisolated struct Raw: Decodable {
        public let name: String
        public let items: [[String]]
    }

    public nonisolated static var count: Int { categories.reduce(0) { $0 + $1.items.count } }

    /// Categories with the items whose class, CSS or example contain `search`, ignoring case; empty categories drop out.
    public nonisolated static func filter(_ search: String) -> [TailwindCategory] {
        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return categories }
        return categories.compactMap { category in
            let items = category.items.filter { item in
                item.name.lowercased().contains(query) || item.css.lowercased().contains(query)
                    || item.example?.lowercased().contains(query) == true
            }
            return items.isEmpty ? nil : TailwindCategory(name: category.name, items: items)
        }
    }

    /// A class and its category, by name.
    public static func lookup(_ name: String) -> (TailwindClass, TailwindCategory)? {
        for category in categories {
            if let item = category.items.first(where: { $0.name == name }) { return (item, category) }
        }
        return nil
    }

    #if DEBUG
    public static func selfCheck() {
        assert(categories.count == 19 && count == 308, "web table and the tip")
        assert(filter("").count == categories.count)
        assert(filter("JUSTIFY-BETWEEN").flatMap(\.items).map(\.name) == ["justify-between"], "case folded")
        assert(filter("group-hover:visible").flatMap(\.items).map(\.name) == ["group-hover:"], "examples match")
        assert(filter("space-evenly").first?.name == "Alignment", "css matches")
        assert(filter("zzz").isEmpty)
        assert(lookup("rotate-45")?.1.name == "Transforms" && lookup("nope") == nil)
        assert(Set(categories.flatMap(\.items).map(\.name)).count == count, "rows are keyed by class")
    }
    #endif
}
