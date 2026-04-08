import Foundation
import PDFKit
import UIKit

struct DocumentLibraryService {
    private let fileStorageService = FileStorageService()
    private let pdfService = PDFService()

    func fetchRecentDocuments() -> [RecentDocumentItem] {
        fileStorageService.listRecentDocuments()
    }

    func loadDocumentData(for item: RecentDocumentItem) throws -> Data {
        try Data(contentsOf: item.fileURL)
    }

    func mergeDocuments(_ items: [RecentDocumentItem], outputName: String? = nil) throws -> RecentDocumentItem {
        let uniqueItems = uniqueDocuments(from: items)
        guard uniqueItems.count >= 2 else {
            throw DocumentLibraryError.needsAtLeastTwoDocuments
        }

        let pdfDataItems = try uniqueItems.map(loadDocumentData)
        guard let mergedPDFData = pdfService.merge(pdfDataItems: pdfDataItems) else {
            throw DocumentLibraryError.mergeFailed
        }

        let mergedName = outputName ?? defaultMergedName(for: uniqueItems)
        let savedURL = try fileStorageService.save(documentData: mergedPDFData, named: mergedName)
        let mergedType = uniqueItems.first?.documentType ?? .general
        let pageCount = PDFDocument(data: mergedPDFData)?.pageCount ?? 0
        fileStorageService.upsertDocumentMetadata(
            for: savedURL,
            name: mergedName,
            documentType: mergedType,
            pageCount: pageCount
        )
        return try recentItem(for: savedURL)
    }

    func exportDocumentAsImages(_ item: RecentDocumentItem) throws -> [URL] {
        let pdfData = try loadDocumentData(for: item)
        let images = pdfService.renderImages(from: pdfData)
        let imageData = pdfService.exportImages(from: images)
        guard !imageData.isEmpty else {
            throw DocumentLibraryError.imageExportFailed
        }

        return try fileStorageService.save(images: imageData, named: item.name)
    }

    func renderedImages(for item: RecentDocumentItem) throws -> [UIImage] {
        let pdfData = try loadDocumentData(for: item)
        let images = pdfService.renderImages(from: pdfData)
        guard !images.isEmpty else {
            throw DocumentLibraryError.imageExportFailed
        }

        return images
    }

    func deleteDocuments(_ items: [RecentDocumentItem]) throws {
        let uniqueItems = uniqueDocuments(from: items)
        guard !uniqueItems.isEmpty else {
            throw DocumentLibraryError.noDocumentsSelected
        }

        do {
            for item in uniqueItems {
                try fileStorageService.deleteDocument(at: item.fileURL)
            }
        } catch {
            throw DocumentLibraryError.deleteFailed
        }
    }

    private func uniqueDocuments(from items: [RecentDocumentItem]) -> [RecentDocumentItem] {
        var seenPaths = Set<String>()
        return items.filter { item in
            seenPaths.insert(item.fileURL.path).inserted
        }
    }

    private func defaultMergedName(for items: [RecentDocumentItem]) -> String {
        let firstName = items.first?.name ?? "Scanova Document"
        if items.count == 2 {
            return "\(firstName) + 1 More"
        }

        return "\(firstName) + \(items.count - 1) More"
    }

    private func recentItem(for url: URL) throws -> RecentDocumentItem {
        let keys: Set<URLResourceKey> = [.contentModificationDateKey, .isRegularFileKey, .fileSizeKey]
        let resourceValues = try url.resourceValues(forKeys: keys)

        guard resourceValues.isRegularFile == true else {
            throw DocumentLibraryError.savedDocumentNotFound
        }

        let pageCount = PDFDocument(url: url)?.pageCount ?? 0
        let name = url.deletingPathExtension().lastPathComponent
        let modifiedAt = resourceValues.contentModificationDate ?? .distantPast
        let fileSizeBytes = resourceValues.fileSize ?? 0

        return RecentDocumentItem(
            id: UUID(),
            name: name,
            modifiedAt: modifiedAt,
            documentType: fileStorageService.listRecentDocuments().first(where: { $0.fileURL.path == url.path })?.documentType ?? .general,
            pageCount: pageCount,
            fileSizeBytes: fileSizeBytes,
            fileURL: url
        )
    }
}

enum DocumentLibraryError: LocalizedError {
    case noDocumentsSelected
    case needsAtLeastTwoDocuments
    case mergeFailed
    case savedDocumentNotFound
    case imageExportFailed
    case deleteFailed

    var errorDescription: String? {
        switch self {
        case .noDocumentsSelected:
            return "Select at least one PDF."
        case .needsAtLeastTwoDocuments:
            return "Select at least two PDFs to merge."
        case .mergeFailed:
            return "Could not merge the selected PDFs."
        case .savedDocumentNotFound:
            return "The merged PDF was saved, but the library could not refresh it."
        case .imageExportFailed:
            return "Could not convert the selected PDF into images."
        case .deleteFailed:
            return "Could not delete the selected PDFs."
        }
    }
}
