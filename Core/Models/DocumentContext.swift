import Foundation
import UIKit

struct DocumentContext {
    let id: UUID
    var pages: [DocumentPage]
    var pdfData: Data?
    var detectedType: DocumentType
    var extractedText: String
    var name: String
    var mode: AppMode
    var selectedPages: Set<Int>
    var isPremiumLocked: Bool
    var importSource: ImportSource?
    var sourceFileURL: URL?
    var enhancementProfile: EnhancementProfile

    init(
        id: UUID = UUID(),
        pages: [DocumentPage] = [],
        pdfData: Data? = nil,
        detectedType: DocumentType = .general,
        extractedText: String = "",
        name: String = "Untitled Scan",
        mode: AppMode = .student,
        selectedPages: Set<Int> = [],
        isPremiumLocked: Bool = false,
        importSource: ImportSource? = nil,
        sourceFileURL: URL? = nil,
        enhancementProfile: EnhancementProfile = .none
    ) {
        self.id = id
        self.pages = pages
        self.pdfData = pdfData
        self.detectedType = detectedType
        self.extractedText = extractedText
        self.name = name
        self.mode = mode
        self.selectedPages = selectedPages
        self.isPremiumLocked = isPremiumLocked
        self.importSource = importSource
        self.sourceFileURL = sourceFileURL
        self.enhancementProfile = enhancementProfile
    }

    var images: [UIImage] {
        pages.map(\.image)
    }

    var pageCount: Int {
        pages.count
    }

    static let empty = DocumentContext()
}
