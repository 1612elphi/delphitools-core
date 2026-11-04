import Foundation

// MARK: - Diff Model

public nonisolated enum DiffLine: Hashable, Sendable {
    case unchanged(text: String, leftIndex: Int, rightIndex: Int)
    case removed(text: String, leftIndex: Int)
    case added(text: String, rightIndex: Int)

    public var text: String {
        switch self {
        case .unchanged(let t, _, _), .removed(let t, _), .added(let t, _): t
        }
    }
}

public nonisolated enum TextDiffer {
    /// Line-by-line diff using Foundation's `CollectionDifference`.
    /// Walks the two line arrays and the difference's removals/insertions in
    /// parallel so unchanged lines preserve their original ordering.
    public static func diff(left: String, right: String) -> [DiffLine] {
        let leftLines = left.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).map(String.init)
        let rightLines = right.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).map(String.init)
        let difference = rightLines.difference(from: leftLines)

        var removalsByIndex: [Int: String] = [:]
        var insertionsByIndex: [Int: String] = [:]
        for change in difference {
            switch change {
            case .remove(let offset, let element, _): removalsByIndex[offset] = element
            case .insert(let offset, let element, _): insertionsByIndex[offset] = element
            }
        }

        var result: [DiffLine] = []
        var li = 0
        var ri = 0
        while li < leftLines.count || ri < rightLines.count {
            if let removed = removalsByIndex[li] {
                result.append(.removed(text: removed, leftIndex: li))
                li += 1
                continue
            }
            if let inserted = insertionsByIndex[ri] {
                result.append(.added(text: inserted, rightIndex: ri))
                ri += 1
                continue
            }
            if li < leftLines.count && ri < rightLines.count {
                result.append(.unchanged(text: leftLines[li], leftIndex: li, rightIndex: ri))
                li += 1
                ri += 1
            } else {
                break
            }
        }
        return result
    }
}
