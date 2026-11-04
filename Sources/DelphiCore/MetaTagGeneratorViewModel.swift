import Foundation

public final class MetaTagGeneratorViewModel {
    public static let ogTypes = ["website", "article", "product"]
    public static let twitterCards = ["summary", "summary_large_image"]

    public var pageTitle: String = ""
    public var description: String = ""
    public var keywords: String = ""
    public var author: String = ""
    public var canonicalURL: String = ""
    public var ogImageURL: String = ""
    public var siteName: String = ""
    public var twitterHandle: String = ""
    public var ogType: String = "website"
    public var twitterCard: String = "summary"

    public var generatedHTML: String {
        var lines: [String] = []

        if !pageTitle.isEmpty {
            lines.append("<title>\(escaped(pageTitle))</title>")
        }
        if !description.isEmpty {
            lines.append("<meta name=\"description\" content=\"\(escaped(description))\">")
        }
        if !keywords.isEmpty {
            lines.append("<meta name=\"keywords\" content=\"\(escaped(keywords))\">")
        }
        if !author.isEmpty {
            lines.append("<meta name=\"author\" content=\"\(escaped(author))\">")
        }
        if !canonicalURL.isEmpty {
            lines.append("<link rel=\"canonical\" href=\"\(escaped(canonicalURL))\">")
        }

        // Open Graph
        lines.append("")
        lines.append("<!-- Open Graph -->")
        if !pageTitle.isEmpty {
            lines.append("<meta property=\"og:title\" content=\"\(escaped(pageTitle))\">")
        }
        if !description.isEmpty {
            lines.append("<meta property=\"og:description\" content=\"\(escaped(description))\">")
        }
        lines.append("<meta property=\"og:type\" content=\"\(ogType)\">")
        if !canonicalURL.isEmpty {
            lines.append("<meta property=\"og:url\" content=\"\(escaped(canonicalURL))\">")
        }
        if !ogImageURL.isEmpty {
            lines.append("<meta property=\"og:image\" content=\"\(escaped(ogImageURL))\">")
        }
        if !siteName.isEmpty {
            lines.append("<meta property=\"og:site_name\" content=\"\(escaped(siteName))\">")
        }

        // Twitter Card
        lines.append("")
        lines.append("<!-- Twitter Card -->")
        lines.append("<meta name=\"twitter:card\" content=\"\(twitterCard)\">")
        if !pageTitle.isEmpty {
            lines.append("<meta name=\"twitter:title\" content=\"\(escaped(pageTitle))\">")
        }
        if !description.isEmpty {
            lines.append("<meta name=\"twitter:description\" content=\"\(escaped(description))\">")
        }
        if !ogImageURL.isEmpty {
            lines.append("<meta name=\"twitter:image\" content=\"\(escaped(ogImageURL))\">")
        }
        if !twitterHandle.isEmpty {
            lines.append("<meta name=\"twitter:creator\" content=\"\(escaped(twitterHandle))\">")
        }

        return lines.joined(separator: "\n")
    }

    private func escaped(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
