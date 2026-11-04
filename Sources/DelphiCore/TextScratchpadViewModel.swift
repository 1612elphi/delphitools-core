import Foundation

@MainActor
public final class TextScratchpadViewModel {
    public var text: String = "" {
        didSet { scheduleSave() }
    }
    public var findText: String = ""
    public var replaceText: String = ""
    public var useRegex: Bool = false
    public var extractedResults: [String] = []

    private static let storageKey = "delphitools-scratchpad"
    private var saveTask: Task<Void, Never>?
    private let persists: Bool

    public init() {
        persists = true
        text = UserDefaults.standard.string(forKey: Self.storageKey) ?? ""
    }

    /// never touches saved draft
    public init(text: String) {
        persists = false
        self.text = text
    }

    // MARK: - Persistence

    private func scheduleSave() {
        guard persists else { return }
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(nanoseconds: 1_000_000_000) // debounce
            guard !Task.isCancelled else { return }
            UserDefaults.standard.set(text, forKey: Self.storageKey)
        }
    }

    // MARK: - Case Operations

    public func toUpperCase() { text = text.uppercased() }
    public func toLowerCase() { text = text.lowercased() }

    public func toTitleCase() {
        text = text.capitalized
    }

    public func toSentenceCase() {
        let lowered = text.lowercased()
        var capitaliseNext = true
        var output = ""
        for char in lowered {
            if capitaliseNext && char.isLetter {
                output.append(char.uppercased())
                capitaliseNext = false
            } else {
                output.append(char)
            }
            if char == "." || char == "!" || char == "?" {
                capitaliseNext = true
            }
        }
        text = output
    }

    public func toCamelCase() {
        let words = text.split { !$0.isLetter && !$0.isNumber }
        guard let first = words.first else { return }
        let rest = words.dropFirst().map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }
        text = first.lowercased() + rest.joined()
    }

    public func toSnakeCase() {
        let words = text.split { !$0.isLetter && !$0.isNumber }
        text = words.map { $0.lowercased() }.joined(separator: "_")
    }

    public func toKebabCase() {
        let words = text.split { !$0.isLetter && !$0.isNumber }
        text = words.map { $0.lowercased() }.joined(separator: "-")
    }

    // MARK: - Line Operations

    public func sortAZ() {
        text = text.components(separatedBy: .newlines).sorted().joined(separator: "\n")
    }

    public func sortZA() {
        text = text.components(separatedBy: .newlines).sorted().reversed().joined(separator: "\n")
    }

    public func sortByLength() {
        text = text.components(separatedBy: .newlines).sorted { $0.count < $1.count }.joined(separator: "\n")
    }

    public func reverseOrder() {
        text = text.components(separatedBy: .newlines).reversed().joined(separator: "\n")
    }

    public func shuffle() {
        text = text.components(separatedBy: .newlines).shuffled().joined(separator: "\n")
    }

    public func removeDuplicates() {
        var seen = Set<String>()
        let lines = text.components(separatedBy: .newlines).filter { seen.insert($0).inserted }
        text = lines.joined(separator: "\n")
    }

    public func addLineNumbers() {
        let lines = text.components(separatedBy: .newlines)
        text = lines.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
    }

    public func removeLineNumbers() {
        let lines = text.components(separatedBy: .newlines)
        text = lines.map { line in
            if let range = line.range(of: #"^\d+[\.\)\:]\s?"#, options: .regularExpression) {
                return String(line[range.upperBound...])
            }
            return line
        }.joined(separator: "\n")
    }

    // MARK: - Cleanup

    public func trimLines() {
        text = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .joined(separator: "\n")
    }

    public func removeEmptyLines() {
        text = text.components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .joined(separator: "\n")
    }

    public func removeExtraSpaces() {
        text = text.replacingOccurrences(of: #" {2,}"#, with: " ", options: .regularExpression)
    }

    public func joinLines() {
        text = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    public func wrapAt(_ width: Int) {
        let words = text.split(separator: " ", omittingEmptySubsequences: true)
        var lines: [String] = []
        var currentLine = ""
        for word in words {
            if currentLine.isEmpty {
                currentLine = String(word)
            } else if currentLine.count + 1 + word.count <= width {
                currentLine += " " + word
            } else {
                lines.append(currentLine)
                currentLine = String(word)
            }
        }
        if !currentLine.isEmpty { lines.append(currentLine) }
        text = lines.joined(separator: "\n")
    }

    public func urlEncode() {
        text = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? text
    }

    public func urlDecode() {
        text = text.removingPercentEncoding ?? text
    }

    // MARK: - Find & Replace

    public func replaceFirst() {
        guard !findText.isEmpty else { return }
        if useRegex {
            guard let regex = try? NSRegularExpression(pattern: findText),
                  let match = regex.matches(in: text, timeLimit: Self.regexTimeLimit)?.first,
                  let range = Range(match.range, in: text) else { return }
            text.replaceSubrange(range, with: regex.replacementString(for: match, in: text, offset: 0, template: replaceText))
        } else if let range = text.range(of: findText, options: .caseInsensitive) {
            text.replaceSubrange(range, with: replaceText)
        }
    }

    public func replaceAll() {
        guard !findText.isEmpty else { return }
        if useRegex {
            guard let regex = try? NSRegularExpression(pattern: findText),
                  let found = regex.matches(in: text, timeLimit: Self.regexTimeLimit) else { return }
            let result = NSMutableString(string: text)
            for match in found.reversed() {
                result.replaceCharacters(in: match.range, with: regex.replacementString(for: match, in: text, offset: 0, template: replaceText))
            }
            text = result as String
        } else {
            text = text.replacingOccurrences(of: findText, with: replaceText, options: .caseInsensitive)
        }
    }

    // MARK: - Extract

    public func extractEmails() {
        extractedResults = extract(pattern: #"[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}"#)
    }

    public func extractURLs() {
        extractedResults = extract(pattern: #"https?://[^\s]+"#)
    }

    public func extractNumbers() {
        extractedResults = extract(pattern: #"-?\d+\.?\d*"#)
    }

    private func extract(pattern: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let nsString = text as NSString
        let results = regex.matches(in: text, range: NSRange(location: 0, length: nsString.length))
        return results.map { nsString.substring(with: $0.range) }
    }
}

extension TextScratchpadViewModel {
    /// seconds; catastrophic backtracking guard
    public nonisolated static let regexTimeLimit = 0.4
}

extension NSRegularExpression {
    /// nil past time limit
    public nonisolated func matches(in text: String, timeLimit: Double) -> [NSTextCheckingResult]? {
        let start = CFAbsoluteTimeGetCurrent()
        var found: [NSTextCheckingResult] = []
        var timedOut = false
        enumerateMatches(in: text, options: .reportProgress, range: NSRange(location: 0, length: (text as NSString).length)) { result, _, stop in
            if CFAbsoluteTimeGetCurrent() - start > timeLimit {
                timedOut = true
                stop.pointee = true
            } else if let result {
                found.append(result)
            }
        }
        return timedOut ? nil : found
    }
}
