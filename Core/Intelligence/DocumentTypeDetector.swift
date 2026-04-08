import Foundation

struct DocumentTypeDetector {
    func detectType(from text: String) -> DocumentType {
        let lowercased = text.lowercased()
        let invoiceScore = score(for: lowercased, keywords: ["invoice", "bill to", "invoice number", "due date", "subtotal"])
        let receiptScore = score(for: lowercased, keywords: ["receipt", "tax", "total", "change", "cash", "visa"])
        let notesScore = score(for: lowercased, keywords: ["chapter", "lecture", "notes", "topic", "summary", "assignment"])

        let ranked: [(DocumentType, Int)] = [
            (.invoice, invoiceScore),
            (.receipt, receiptScore),
            (.notes, notesScore),
            (.general, 0)
        ]

        return ranked.max(by: { $0.1 < $1.1 })?.1 == 0 ? .general : ranked.max(by: { $0.1 < $1.1 })!.0
    }

    private func score(for text: String, keywords: [String]) -> Int {
        keywords.reduce(0) { partial, keyword in
            partial + (text.contains(keyword) ? 1 : 0)
        }
    }
}
