import Foundation

// tracking parameters and share cruft off a link
public enum LinkCleaner {
    // ponytail: one list plus amazon and youtube; per-site rules when a real case shows up
    static let prefixes = ["utm_", "hs_", "pk_", "mtm_", "vero_", "oly_", "mc_"]
    static let keys: Set<String> = [
        "fbclid", "gclid", "gclsrc", "dclid", "gbraid", "wbraid", "msclkid", "yclid", "twclid", "ttclid",
        "igshid", "igsh", "li_fat_id", "_hsenc", "_hsmi", "mkt_tok", "s_kwcid", "_ga", "_gl", "srsltid",
        "ocid", "cmpid", "ncid", "ref_src", "ref_url", "spm", "sharer",
    ]
    static let video: Set<String> = ["si", "feature", "pp"]

    public static func clean(_ string: String) -> String {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        // lenient parsing percent-encodes plain text
        guard let url = URL(string: trimmed), url.scheme != nil, url.host() != nil else { return string }
        return clean(url).absoluteString
    }

    public static func clean(_ url: URL) -> URL {
        guard var parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        let host = (parts.host ?? "").lowercased()
        if host.contains("amazon."), let range = parts.path.range(of: #"/(dp|gp/product)/[A-Z0-9]{10}"#, options: .regularExpression),
           let asin = parts.path[range].split(separator: "/").last {
            parts.path = "/dp/\(asin)"
            parts.query = nil
        }
        if let items = parts.percentEncodedQueryItems {
            let kept = items.filter { !isTracking($0.name.lowercased(), host: host) }
            parts.percentEncodedQueryItems = kept.isEmpty ? nil : kept
        }
        // chrome text fragments
        if parts.fragment?.hasPrefix(":~:") == true { parts.fragment = nil }
        return parts.url ?? url
    }

    static func isTracking(_ name: String, host: String) -> Bool {
        if keys.contains(name) || prefixes.contains(where: name.hasPrefix) { return true }
        let isVideo = host.hasSuffix("youtube.com") || host.hasSuffix("youtu.be")
        return isVideo && video.contains(name)
    }
}
