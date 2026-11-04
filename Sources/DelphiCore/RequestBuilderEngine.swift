import Foundation

public struct RequestPair: Identifiable, Sendable {
    public let id = UUID()
    public var key: String = ""
    public var value: String = ""

    public init(key: String = "", value: String = "") {
        self.key = key
        self.value = value
    }
}

public struct RequestSpec: Sendable {
    public var method: String = "GET"
    public var url: String = ""
    public var params: [RequestPair] = []
    public var headers: [RequestPair] = []
    public var body: String = ""

    public init(method: String = "GET", url: String = "", params: [RequestPair] = [], headers: [RequestPair] = [], body: String = "") {
        self.method = method
        self.url = url
        self.params = params
        self.headers = headers
        self.body = body
    }
}

/// Composes request text only. Nothing here opens a connection.
public enum RequestBuilderEngine {

    public static let methods = ["GET", "POST", "PUT", "PATCH", "DELETE", "HEAD", "OPTIONS"]

    // matches encodeURIComponent
    private static let componentAllowed = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.!~*'()")

    private static func live(_ pairs: [RequestPair]) -> [RequestPair] {
        pairs.filter { !$0.key.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    private static func hasHeader(_ headers: [RequestPair], _ name: String) -> Bool {
        headers.contains {
            $0.key.trimmingCharacters(in: .whitespaces).lowercased() == name
        }
    }

    private static func encode(_ text: String) -> String {
        text.addingPercentEncoding(withAllowedCharacters: componentAllowed) ?? text
    }

    // escape posix quotes
    private static func quote(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    public static func fullURL(_ spec: RequestSpec) -> String {
        let extra = live(spec.params)
            .map { "\(encode($0.key.trimmingCharacters(in: .whitespaces)))=\(encode($0.value))" }
            .joined(separator: "&")
        if extra.isEmpty { return spec.url }
        return spec.url + (spec.url.contains("?") ? "&" : "?") + extra
    }

    public static func toCurl(_ spec: RequestSpec) -> String {
        let url = quote(fullURL(spec))
        var parts: [String] = []
        switch spec.method {
        case "GET": parts.append("curl \(url)")
        case "HEAD": parts.append("curl -I \(url)")
        default: parts.append("curl -X \(spec.method) \(url)")
        }
        for pair in live(spec.headers) {
            parts.append("-H " + quote("\(pair.key.trimmingCharacters(in: .whitespaces)): \(pair.value)"))
        }
        if !spec.body.isEmpty { parts.append("--data-raw " + quote(spec.body)) }
        return parts.joined(separator: " \\\n  ")
    }

    public static func toHTTP(_ spec: RequestSpec) -> String {
        let full = fullURL(spec)
        var host = ""
        var target = full.isEmpty ? "/" : full

        if let url = URL(string: full), let urlHost = url.host, url.scheme != nil {
            let bracketed = urlHost.contains(":") ? "[\(urlHost)]" : urlHost
            host = url.port.map { "\(bracketed):\($0)" } ?? bracketed
            let path = url.path(percentEncoded: true)
            target = (path.isEmpty ? "/" : path)
                + (url.query(percentEncoded: true).map { "?\($0)" } ?? "")
        }

        let headers = live(spec.headers)
        var lines = ["\(spec.method) \(target.isEmpty ? "/" : target) HTTP/1.1"]
        if !host.isEmpty, !hasHeader(headers, "host") { lines.append("Host: \(host)") }
        for pair in headers {
            lines.append("\(pair.key.trimmingCharacters(in: .whitespaces)): \(pair.value)")
        }
        if !spec.body.isEmpty, !hasHeader(headers, "content-length") {
            lines.append("Content-Length: \(spec.body.utf8.count)")
        }

        return lines.joined(separator: "\n") + (spec.body.isEmpty ? "\n" : "\n\n\(spec.body)")
    }

    #if DEBUG
    public static func selfCheck() {
        var spec = RequestSpec(method: "POST", url: "https://api.example.com/path?a=1")
        spec.params = [RequestPair(key: "q", value: "a b&c"), RequestPair(key: "  ", value: "skip")]
        spec.headers = [RequestPair(key: " Content-Type ", value: "application/json")]
        spec.body = #"{"x":1}"#

        assert(fullURL(spec) == "https://api.example.com/path?a=1&q=a%20b%26c")
        assert(toCurl(spec) == """
        curl -X POST 'https://api.example.com/path?a=1&q=a%20b%26c' \\
          -H 'Content-Type: application/json' \\
          --data-raw '{"x":1}'
        """)
        assert(toHTTP(spec) == """
        POST /path?a=1&q=a%20b%26c HTTP/1.1
        Host: api.example.com
        Content-Type: application/json
        Content-Length: 7

        {"x":1}
        """)

        let bare = RequestSpec(method: "GET", url: "https://example.com")
        assert(toCurl(bare) == "curl 'https://example.com'")
        assert(toHTTP(bare) == "GET / HTTP/1.1\nHost: example.com\n")

        var head = RequestSpec(method: "HEAD", url: "https://example.com/x")
        head.headers = [RequestPair(key: "Host", value: "other.example")]
        assert(head.method == "HEAD")
        assert(toCurl(head).hasPrefix("curl -I "))
        assert(!toHTTP(head).contains("Host: example.com"))

        let quoted = RequestSpec(method: "GET", url: "https://x.test/it's")
        assert(toCurl(quoted).contains(#"'https://x.test/it'\''s'"#))

        var awkward = RequestSpec(method: "POST", url: "http://[::1]:8080/a")
        awkward.body = "é'\n$(id)`x`"
        assert(toCurl(awkward).hasSuffix("--data-raw 'é'\\''\n$(id)`x`'"))
        assert(toHTTP(awkward).contains("Host: [::1]:8080\nContent-Length: 12\n"))
    }
    #endif
}
