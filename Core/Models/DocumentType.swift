import Foundation

enum DocumentType: String, CaseIterable, Codable {
    case notes
    case invoice
    case receipt
    case general
}

extension DocumentType {
    var menuTitle: String {
        switch self {
        case .notes:
            return "Notes"
        case .invoice:
            return "Invoices"
        case .receipt:
            return "Receipts"
        case .general:
            return "General"
        }
    }
}
