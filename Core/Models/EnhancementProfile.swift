import Foundation

enum EnhancementProfile: String, Codable {
    case none
    case document
    case receipt
    case invoice
    case notes

    var displayTitle: String {
        switch self {
        case .none:
            return "Original"
        case .document:
            return "Optimized for Document"
        case .receipt:
            return "Optimized for Receipt"
        case .invoice:
            return "Optimized for Invoice"
        case .notes:
            return "Optimized for Notes"
        }
    }
}
