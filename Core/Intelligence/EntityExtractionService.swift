import Foundation

struct ExtractedEntities {
    var dates: [String] = []
    var amounts: [String] = []
    var invoiceNumbers: [String] = []
    var keywords: [String] = []
    var title: String?
    var vendor: String?
}

struct EntityExtractionService {
    func extract(from text: String) -> ExtractedEntities {
        let normalizedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedText.isEmpty else { return ExtractedEntities() }

        let lines = normalizedText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var entities = ExtractedEntities()
        entities.title = lines.first
        entities.vendor = lines.first(where: { $0.count > 2 && $0.count < 40 })
        entities.dates = detectDates(in: normalizedText)
        entities.amounts = detectMatches(in: normalizedText, pattern: #"\$?\d{1,3}(?:,\d{3})*(?:\.\d{2})?"#)
        entities.invoiceNumbers = detectMatches(in: normalizedText, pattern: #"(?i)(?:invoice|inv)[\s#:-]*([A-Z0-9-]{3,})"#)
        entities.keywords = detectKeywords(from: normalizedText)
        return entities
    }

    private func detectDates(in text: String) -> [String] {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) else {
            return []
        }

        let nsText = text as NSString
        let matches = detector.matches(in: text, range: NSRange(location: 0, length: nsText.length))
        let formatter = DateFormatter()
        formatter.dateStyle = .medium

        return Array(Set(matches.compactMap { match in
            guard let date = match.date else { return nil }
            return formatter.string(from: date)
        })).sorted()
    }

    private func detectMatches(in text: String, pattern: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let nsText = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))

        let values = matches.compactMap { match -> String? in
            guard match.numberOfRanges > 1 else {
                return nsText.substring(with: match.range)
            }

            return nsText.substring(with: match.range(at: 1))
        }

        return Array(Set(values)).sorted()
    }

    private func detectKeywords(from text: String) -> [String] {
        let stopWords: Set<String> = ["the", "and", "for", "with", "from", "that", "this", "scan", "page", "document"]

        let words = text
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 4 && !stopWords.contains($0) }

        var counts: [String: Int] = [:]
        for word in words {
            counts[word, default: 0] += 1
        }

        return counts
            .sorted { lhs, rhs in
                if lhs.value == rhs.value {
                    return lhs.key < rhs.key
                }
                return lhs.value > rhs.value
            }
            .map(\.key)
            .prefix(5)
            .map { $0.capitalized }
    }
}
