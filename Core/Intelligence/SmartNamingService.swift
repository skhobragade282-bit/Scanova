import Foundation

struct SmartNamingService {
    private let preferredMaximumLength = 28
    private let hardMaximumLength = 24

    func makeName(for type: DocumentType, entities: ExtractedEntities, mode: AppMode) -> String {
        let primary = bestPrimaryName(for: type, entities: entities, mode: mode)
        let detail = bestDetail(for: type, entities: entities, excluding: primary, mode: mode)
        let composed = composeName(primary: primary, detail: detail)
        return truncateIfNeeded(composed)
    }

    private func bestPrimaryName(for type: DocumentType, entities: ExtractedEntities, mode: AppMode) -> String {
        switch type {
        case .invoice:
            return firstReadable(
                entities.vendor,
                entities.title,
                entities.keywords.first,
                "Invoice"
            )
        case .receipt:
            return firstReadable(
                entities.vendor,
                entities.title,
                entities.keywords.first,
                "Receipt"
            )
        case .notes:
            return firstReadable(
                shortenedPhrase(entities.title),
                entities.keywords.first,
                mode == .student ? "Study Notes" : "Notes"
            )
        case .general:
            return firstReadable(
                shortenedPhrase(entities.title),
                entities.keywords.first,
                mode == .student ? "Study Scan" : "Document Scan"
            )
        }
    }

    private func bestDetail(for type: DocumentType, entities: ExtractedEntities, excluding primary: String, mode: AppMode) -> String? {
        if let firstDate = entities.dates.first {
            return shortDate(firstDate)
        }

        let keyword = entities.keywords
            .map(sanitizeCandidate)
            .first { !$0.isEmpty && $0.caseInsensitiveCompare(primary) != .orderedSame }

        switch type {
        case .invoice, .receipt:
            return keyword
        case .notes:
            return keyword ?? (mode == .student ? nil : "Notes")
        case .general:
            return nil
        }
    }

    private func composeName(primary: String, detail: String?) -> String {
        guard let detail, !detail.isEmpty else {
            return primary
        }

        let candidate = "\(primary) - \(detail)"
        return candidate.count <= preferredMaximumLength ? candidate : primary
    }

    private func firstReadable(_ values: String?...) -> String {
        for value in values {
            guard let value else { continue }
            let cleaned = sanitizeCandidate(value)
            if !cleaned.isEmpty {
                return cleaned
            }
        }

        return "Untitled Scan"
    }

    private func shortenedPhrase(_ value: String?) -> String? {
        guard let value else { return nil }
        let cleaned = sanitizeCandidate(value)
        guard !cleaned.isEmpty else { return nil }

        let words = cleaned.split(separator: " ").map(String.init)
        guard !words.isEmpty else { return nil }
        return words.prefix(3).joined(separator: " ")
    }

    private func shortDate(_ value: String) -> String {
        let parts = value
            .replacingOccurrences(of: ",", with: "")
            .split(separator: " ")
            .map(String.init)

        if parts.count >= 2 {
            return parts.prefix(2).joined(separator: " ")
        }

        return value
    }

    private func truncateIfNeeded(_ value: String) -> String {
        let cleaned = value
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard cleaned.count > preferredMaximumLength else { return cleaned }

        let words = cleaned.split(separator: " ").map(String.init)
        var result: [String] = []

        for word in words {
            let candidate = (result + [word]).joined(separator: " ")
            if candidate.count > hardMaximumLength {
                break
            }
            result.append(word)
        }

        if result.isEmpty {
            return String(cleaned.prefix(hardMaximumLength))
        }

        return result.joined(separator: " ")
    }

    private func sanitizeCandidate(_ value: String) -> String {
        let cleaned = value
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .punctuationCharacters.subtracting(CharacterSet(charactersIn: "-&")))
            .joined(separator: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return isReadable(cleaned) ? cleaned : ""
    }

    private func isReadable(_ value: String) -> Bool {
        guard !value.isEmpty else { return false }
        guard value.count <= 36 else { return false }

        let lowercase = value.lowercased()
        let rejectedFragments = [
            "environmentobject",
            "stateobject",
            "observedobject",
            "binding",
            "viewbuilder",
            "swiftui",
            "func ",
            "struct ",
            "class "
        ]

        if rejectedFragments.contains(where: { lowercase.contains($0) }) {
            return false
        }

        let words = value.split(separator: " ")
        if words.count == 1 {
            let token = String(words[0])
            let looksLikeLongCamelCase = token.range(of: #"[a-z][A-Z]"#, options: .regularExpression) != nil && token.count > 10
            if looksLikeLongCamelCase {
                return false
            }
        }

        return true
    }
}
