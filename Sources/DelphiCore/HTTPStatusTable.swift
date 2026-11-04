import Foundation

public enum HTTPRegistryState: Sendable {
    case standard, deprecated, unused

    public var label: String {
        switch self {
        case .standard: String(localized: "Standard")
        case .deprecated: String(localized: "Deprecated")
        case .unused: String(localized: "Unused")
        }
    }
}

public struct HTTPStatusEntry: Sendable {
    public let code: Int
    public let phrase: String
    public let statusClass: Int
    public let reference: String
    public let isCacheable: Bool
    public let registry: HTTPRegistryState

    public var facts: String {
        [reference, isCacheable ? String(localized: "Cacheable") : nil, registry == .standard ? nil : registry.label]
            .compactMap { $0 }.joined(separator: " · ")
    }
}

public struct HTTPStatusGroup: Sendable {
    public let statusClass: Int
    public let name: String
    public let items: [HTTPStatusEntry]
}

public enum HTTPStatusTable {

    public static let classNames: [(statusClass: Int, name: String)] = [
        (1, String(localized: "Informational")),
        (2, String(localized: "Successful")),
        (3, String(localized: "Redirection")),
        (4, String(localized: "Client Error")),
        (5, String(localized: "Server Error")),
    ]

    public static let defaultCacheable: Set<Int> = [
        200, 203, 204, 206, 300, 301, 308, 404, 405, 410, 414, 501,
    ]

    private static func entry(_ code: Int, _ phrase: String, _ statusClass: Int,
                              _ rfc: Int, _ section: String,
                              _ registry: HTTPRegistryState = .standard) -> HTTPStatusEntry {
        HTTPStatusEntry(
            code: code,
            phrase: phrase,
            statusClass: statusClass,
            reference: "RFC \(rfc) §\(section)",
            isCacheable: defaultCacheable.contains(code),
            registry: registry
        )
    }

    public static let all: [HTTPStatusEntry] = [
        entry(100, "Continue", 1, 9110, "15.2.1"),
        entry(101, "Switching Protocols", 1, 9110, "15.2.2"),
        entry(102, "Processing", 1, 2518, "10.1"),
        entry(103, "Early Hints", 1, 8297, "2"),

        entry(200, "OK", 2, 9110, "15.3.1"),
        entry(201, "Created", 2, 9110, "15.3.2"),
        entry(202, "Accepted", 2, 9110, "15.3.3"),
        entry(203, "Non-Authoritative Information", 2, 9110, "15.3.4"),
        entry(204, "No Content", 2, 9110, "15.3.5"),
        entry(205, "Reset Content", 2, 9110, "15.3.6"),
        entry(206, "Partial Content", 2, 9110, "15.3.7"),
        entry(207, "Multi-Status", 2, 4918, "11.1"),
        entry(208, "Already Reported", 2, 5842, "7.1"),
        entry(226, "IM Used", 2, 3229, "10.4.1"),

        entry(300, "Multiple Choices", 3, 9110, "15.4.1"),
        entry(301, "Moved Permanently", 3, 9110, "15.4.2"),
        entry(302, "Found", 3, 9110, "15.4.3"),
        entry(303, "See Other", 3, 9110, "15.4.4"),
        entry(304, "Not Modified", 3, 9110, "15.4.5"),
        entry(305, "Use Proxy", 3, 9110, "15.4.6", .deprecated),
        entry(306, "(Unused)", 3, 9110, "15.4.7", .unused),
        entry(307, "Temporary Redirect", 3, 9110, "15.4.8"),
        entry(308, "Permanent Redirect", 3, 9110, "15.4.9"),

        entry(400, "Bad Request", 4, 9110, "15.5.1"),
        entry(401, "Unauthorized", 4, 9110, "15.5.2"),
        entry(402, "Payment Required", 4, 9110, "15.5.3"),
        entry(403, "Forbidden", 4, 9110, "15.5.4"),
        entry(404, "Not Found", 4, 9110, "15.5.5"),
        entry(405, "Method Not Allowed", 4, 9110, "15.5.6"),
        entry(406, "Not Acceptable", 4, 9110, "15.5.7"),
        entry(407, "Proxy Authentication Required", 4, 9110, "15.5.8"),
        entry(408, "Request Timeout", 4, 9110, "15.5.9"),
        entry(409, "Conflict", 4, 9110, "15.5.10"),
        entry(410, "Gone", 4, 9110, "15.5.11"),
        entry(411, "Length Required", 4, 9110, "15.5.12"),
        entry(412, "Precondition Failed", 4, 9110, "15.5.13"),
        entry(413, "Content Too Large", 4, 9110, "15.5.14"),
        entry(414, "URI Too Long", 4, 9110, "15.5.15"),
        entry(415, "Unsupported Media Type", 4, 9110, "15.5.16"),
        entry(416, "Range Not Satisfiable", 4, 9110, "15.5.17"),
        entry(417, "Expectation Failed", 4, 9110, "15.5.18"),
        entry(418, "I'm a Teapot", 4, 9110, "15.5.19", .unused),
        entry(421, "Misdirected Request", 4, 9110, "15.5.20"),
        entry(422, "Unprocessable Content", 4, 9110, "15.5.21"),
        entry(423, "Locked", 4, 4918, "11.3"),
        entry(424, "Failed Dependency", 4, 4918, "11.4"),
        entry(425, "Too Early", 4, 8470, "5.2"),
        entry(426, "Upgrade Required", 4, 9110, "15.5.22"),
        entry(428, "Precondition Required", 4, 6585, "3"),
        entry(429, "Too Many Requests", 4, 6585, "4"),
        entry(431, "Request Header Fields Too Large", 4, 6585, "5"),
        entry(451, "Unavailable For Legal Reasons", 4, 7725, "3"),

        entry(500, "Internal Server Error", 5, 9110, "15.6.1"),
        entry(501, "Not Implemented", 5, 9110, "15.6.2"),
        entry(502, "Bad Gateway", 5, 9110, "15.6.3"),
        entry(503, "Service Unavailable", 5, 9110, "15.6.4"),
        entry(504, "Gateway Timeout", 5, 9110, "15.6.5"),
        entry(505, "HTTP Version Not Supported", 5, 9110, "15.6.6"),
        entry(506, "Variant Also Negotiates", 5, 2295, "8.1"),
        entry(507, "Insufficient Storage", 5, 4918, "11.5"),
        entry(508, "Loop Detected", 5, 5842, "7.2"),
        entry(510, "Not Extended", 5, 2774, "7"),
        entry(511, "Network Authentication Required", 5, 6585, "6"),
    ]

    public static func count(of statusClass: Int) -> Int {
        all.filter { $0.statusClass == statusClass }.count
    }

    public static func groups(search: String, statusClass: Int?) -> [HTTPStatusGroup] {
        var statuses = statusClass.map { wanted in
            all.filter { $0.statusClass == wanted }
        } ?? all

        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        if !query.isEmpty {
            statuses = statuses.filter {
                String($0.code).contains(query) || $0.phrase.lowercased().contains(query)
            }
        }

        return classNames.compactMap { info in
            let items = statuses.filter { $0.statusClass == info.statusClass }
            guard !items.isEmpty else { return nil }
            return HTTPStatusGroup(statusClass: info.statusClass, name: info.name, items: items)
        }
    }

    public static func lookup(_ code: Int) -> HTTPStatusEntry? {
        all.first { $0.code == code }
    }

    #if DEBUG
    public static func selfCheck() {
        assert(all.count == 63)
        assert(lookup(418)?.registry == .unused)
        assert(lookup(200)?.isCacheable == true)
        assert(lookup(201)?.isCacheable == false)
        assert(lookup(404)?.reference == "RFC 9110 §15.5.5")
        assert(groups(search: "40", statusClass: nil).count == 1)
        assert(groups(search: "teapot", statusClass: nil).first?.items.first?.code == 418)
        assert(groups(search: "", statusClass: 5).first?.items.count == count(of: 5))
    }
    #endif
}
