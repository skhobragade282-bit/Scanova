import Foundation

struct StoredDocumentRecord: Codable, Equatable {
    var filePath: String
    var name: String
    var documentType: DocumentType
    var pageCount: Int
    var modifiedAt: Date
}
