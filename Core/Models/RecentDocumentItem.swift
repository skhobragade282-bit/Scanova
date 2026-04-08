import Foundation

struct RecentDocumentItem: Identifiable, Equatable, Codable {
    let id: UUID
    var name: String
    var modifiedAt: Date
    var documentType: DocumentType
    var pageCount: Int
    var fileSizeBytes: Int
    var fileURL: URL
}
