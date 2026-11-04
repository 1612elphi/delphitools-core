import Foundation

extension DocConvert {
    /// What a document holds, one row per kind of element: how many and the first of them.
    public enum Ledger {
        public enum Element: CaseIterable, Sendable {
            case heading, paragraph, bullets, numbered, quote, code, rule, bold, italic, codeSpan, link

            public var mark: String {
                switch self {
                case .heading: "H"
                case .paragraph: "\u{00B6}"
                case .bullets: "\u{2022}"
                case .numbered: "1."
                case .quote: "\u{201C}"
                case .code: "{ }"
                case .rule: "\u{2014}"
                case .bold: "B"
                case .italic: "I"
                case .codeSpan: "` `"
                case .link: "\u{2197}"
                }
            }
        }

        public struct Row: Equatable, Sendable {
            public let element: Element
            public let count: Int
            public let example: Block
        }

        public static func rows(_ blocks: [Block]) -> [Row] {
            var counts: [Element: Int] = [:]
            var examples: [Element: Block] = [:]
            func add(_ element: Element, _ example: @autoclosure () -> Block) {
                counts[element, default: 0] += 1
                if examples[element] == nil { examples[element] = example() }
            }
            func inline(_ runs: [Inline]) {
                for run in runs {
                    if run.bold { add(.bold, .paragraph([run])) }
                    if run.italic { add(.italic, .paragraph([run])) }
                    if run.code { add(.codeSpan, .paragraph([run])) }
                    if run.link != nil { add(.link, .paragraph([run])) }
                }
            }
            for block in blocks {
                switch block {
                case .heading(_, let runs): add(.heading, block); inline(runs)
                case .paragraph(let runs): add(.paragraph, block); inline(runs)
                case .quote(let runs): add(.quote, block); inline(runs)
                case .list(let ordered, let items):
                    add(ordered ? .numbered : .bullets, .list(ordered: ordered, items: Array(items.prefix(1))))
                    items.forEach(inline)
                case .code: add(.code, block)
                case .rule: add(.rule, block)
                }
            }
            return Element.allCases.compactMap { element in
                guard let count = counts[element], let example = examples[element] else { return nil }
                return Row(element: element, count: count, example: example)
            }
        }

        /// Plain text drops the element's mark-up.
        public static func isLost(_ element: Element, in format: Format) -> Bool {
            format == .plain && [.heading, .quote, .bold, .italic, .codeSpan, .link].contains(element)
        }

        /// The block in a text format on one line.
        public static func line(_ block: Block, as format: Format) -> String {
            let text = switch format {
            case .markdown: markdown([block])
            case .html: html([block], standalone: false)
            default: plain([block])
            }
            return text.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: " ")
        }

        #if DEBUG
        public static func selfCheck() {
            let blocks = parseMarkdown("# A\n\nSome **b** and [c](https://x).\n\n- one\n- two\n\n# D")
            let found = rows(blocks)
            assert(found.map(\.element) == [.heading, .paragraph, .bullets, .bold, .link], "kinds in order")
            assert(found[0].count == 2 && found[2].count == 1, "counts")
            assert(line(found[0].example, as: .html) == "<h1>A</h1>")
            assert(line(found[2].example, as: .markdown) == "- one", "a list's first item")
            assert(line(found[3].example, as: .plain) == "b" && isLost(.bold, in: .plain) && !isLost(.bold, in: .rtf))
        }
        #endif
    }
}
