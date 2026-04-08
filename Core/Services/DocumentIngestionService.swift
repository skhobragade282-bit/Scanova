import Foundation
import PDFKit
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct ImportedDocument {
    var pages: [DocumentPage]
    var source: ImportSource
    var sourceFileURL: URL?
}

enum DocumentImportError: LocalizedError {
    case unsupportedFileType
    case unreadableImage
    case unreadablePDF
    case passwordRequired
    case incorrectPassword
    case emptySelection

    var errorDescription: String? {
        switch self {
        case .unsupportedFileType:
            return "That file type is not supported yet."
        case .unreadableImage:
            return "The selected image could not be loaded."
        case .unreadablePDF:
            return "The selected PDF could not be opened."
        case .passwordRequired:
            return "Enter the password to open this PDF."
        case .incorrectPassword:
            return "That password didn’t work. Try again."
        case .emptySelection:
            return "Please choose at least one file or image."
        }
    }
}

struct DocumentIngestionService {
    func importScannedImages(_ images: [UIImage]) throws -> ImportedDocument {
        guard !images.isEmpty else { throw DocumentImportError.emptySelection }

        let pages = images.enumerated().map { index, image in
            DocumentPage(image: image, originalImage: image, source: .camera, sourcePageIndex: index)
        }

        return ImportedDocument(pages: pages, source: .camera, sourceFileURL: nil)
    }

    func importPhotos(from items: [PhotosPickerItem]) async throws -> ImportedDocument {
        guard !items.isEmpty else { throw DocumentImportError.emptySelection }

        var pages: [DocumentPage] = []
        for item in items {
            if let data = try await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                pages.append(DocumentPage(image: image, originalImage: image, source: .photoLibrary))
            }
        }

        guard !pages.isEmpty else { throw DocumentImportError.unreadableImage }
        return ImportedDocument(pages: pages, source: .photoLibrary, sourceFileURL: nil)
    }

    func importFile(from url: URL, password: String? = nil) throws -> ImportedDocument {
        let needsScopedAccess = url.startAccessingSecurityScopedResource()
        defer {
            if needsScopedAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        guard let type = UTType(filenameExtension: url.pathExtension) else {
            throw DocumentImportError.unsupportedFileType
        }

        if type.conforms(to: .pdf) {
            return try importPDF(from: url, password: password)
        }

        if type.conforms(to: .image) {
            return try importImageFile(from: url)
        }

        throw DocumentImportError.unsupportedFileType
    }

    private func importImageFile(from url: URL) throws -> ImportedDocument {
        guard let data = try? Data(contentsOf: url),
              let image = UIImage(data: data) else {
            throw DocumentImportError.unreadableImage
        }

        return ImportedDocument(
            pages: [DocumentPage(image: image, originalImage: image, source: .filesImage, sourcePageIndex: 0)],
            source: .filesImage,
            sourceFileURL: url
        )
    }

    private func importPDF(from url: URL, password: String? = nil) throws -> ImportedDocument {
        guard let document = PDFDocument(url: url) else {
            throw DocumentImportError.unreadablePDF
        }

        if document.isLocked {
            guard let password, !password.isEmpty else {
                throw DocumentImportError.passwordRequired
            }

            guard document.unlock(withPassword: password) else {
                throw DocumentImportError.incorrectPassword
            }
        }

        var pages: [DocumentPage] = []
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { continue }
            let bounds = page.bounds(for: .mediaBox)
            let format = UIGraphicsImageRendererFormat()
            format.scale = 2
            let renderer = UIGraphicsImageRenderer(size: bounds.size, format: format)
            let image = renderer.image { context in
                UIColor.white.setFill()
                context.fill(CGRect(origin: .zero, size: bounds.size))

                context.cgContext.translateBy(x: 0, y: bounds.height)
                context.cgContext.scaleBy(x: 1, y: -1)
                page.draw(with: .mediaBox, to: context.cgContext)
            }

            pages.append(DocumentPage(image: image, originalImage: image, source: .filesPDF, sourcePageIndex: index))
        }

        guard !pages.isEmpty else { throw DocumentImportError.unreadablePDF }

        return ImportedDocument(
            pages: pages,
            source: .filesPDF,
            sourceFileURL: url
        )
    }
}
