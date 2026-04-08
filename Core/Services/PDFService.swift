import Foundation
import PDFKit
import UIKit

struct PDFService {
    func createPDFData(from images: [UIImage], compressionQuality: CGFloat? = nil) -> Data? {
        guard !images.isEmpty else { return nil }

        let renderImages: [UIImage]
        if let compressionQuality {
            renderImages = images.map { compressedImage(from: $0, quality: compressionQuality) }
        } else {
            renderImages = images
        }

        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: PDFPageLayout.defaultPageSize))

        return renderer.pdfData { context in
            for image in renderImages {
                let pageBounds = CGRect(origin: .zero, size: PDFPageLayout.pageSize(for: image))
                context.beginPage(withBounds: pageBounds, pageInfo: [:])
                draw(image: image, in: pageBounds)
            }
        }
    }

    func merge(pdfDataItems: [Data]) -> Data? {
        guard !pdfDataItems.isEmpty else { return nil }
        let mergedDocument = PDFDocument()
        var insertionIndex = 0

        for data in pdfDataItems {
            guard let document = PDFDocument(data: data) else { continue }

            for pageIndex in 0..<document.pageCount {
                guard let page = document.page(at: pageIndex)?.copy() as? PDFPage else { continue }
                mergedDocument.insert(page, at: insertionIndex)
                insertionIndex += 1
            }
        }

        return insertionIndex == 0 ? nil : mergedDocument.dataRepresentation()
    }

    func extractSelectedPages(from pdfData: Data, pages: Set<Int>) -> Data? {
        guard !pages.isEmpty else { return nil }
        guard let document = PDFDocument(data: pdfData) else { return nil }

        let extractedDocument = PDFDocument()
        let sortedIndexes = pages.sorted()
        var insertionIndex = 0

        for index in sortedIndexes {
            guard let page = document.page(at: index)?.copy() as? PDFPage else { continue }
            extractedDocument.insert(page, at: insertionIndex)
            insertionIndex += 1
        }

        return insertionIndex == 0 ? nil : extractedDocument.dataRepresentation()
    }

    func exportImages(from images: [UIImage]) -> [Data] {
        images.compactMap { $0.pngData() }
    }

    func renderImages(from pdfData: Data) -> [UIImage] {
        guard let document = PDFDocument(data: pdfData) else { return [] }

        return (0..<document.pageCount).compactMap { index in
            guard let page = document.page(at: index) else { return nil }
            return renderImage(for: page)
        }
    }

    func removeSelectedPages(from pdfData: Data, pages: Set<Int>) -> Data? {
        guard let document = PDFDocument(data: pdfData) else { return nil }

        let mutableDocument = PDFDocument()
        var insertionIndex = 0

        for index in 0..<document.pageCount where !pages.contains(index) {
            guard let page = document.page(at: index)?.copy() as? PDFPage else { continue }
            mutableDocument.insert(page, at: insertionIndex)
            insertionIndex += 1
        }

        return insertionIndex == 0 ? nil : mutableDocument.dataRepresentation()
    }

    func split(pdfData: Data, selectedPages: Set<Int>) -> (selected: Data?, remainder: Data?) {
        let selected = extractSelectedPages(from: pdfData, pages: selectedPages)
        let remainder = removeSelectedPages(from: pdfData, pages: selectedPages)
        return (selected, remainder)
    }

    func passwordProtectedPDFData(from pdfData: Data, userPassword: String, ownerPassword: String? = nil) -> Data? {
        guard let document = PDFDocument(data: pdfData) else { return nil }

        return document.dataRepresentation(options: [
            PDFDocumentWriteOption.userPasswordOption: userPassword,
            PDFDocumentWriteOption.ownerPasswordOption: ownerPassword ?? userPassword
        ])
    }

    private func draw(image: UIImage, in pageBounds: CGRect) {
        let imageSize = image.size
        guard imageSize.width > 0, imageSize.height > 0 else { return }
        image.draw(in: pageBounds)
    }

    private func compressedImage(from image: UIImage, quality: CGFloat) -> UIImage {
        guard let jpegData = image.jpegData(compressionQuality: quality),
              let compressedImage = UIImage(data: jpegData, scale: image.scale) else {
            return image
        }

        return compressedImage
    }

    private func renderImage(for page: PDFPage) -> UIImage? {
        let bounds = page.bounds(for: .mediaBox)
        let size = CGSize(width: max(bounds.width, 1), height: max(bounds.height, 1))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2

        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            context.cgContext.translateBy(x: 0, y: size.height)
            context.cgContext.scaleBy(x: 1, y: -1)
            page.draw(with: .mediaBox, to: context.cgContext)
        }
    }
}

private enum PDFPageLayout {
    static let defaultPageSize = CGSize(width: 612, height: 792)

    static func pageSize(for image: UIImage) -> CGSize {
        let normalizedSize = image.size
        guard normalizedSize.width > 0, normalizedSize.height > 0 else {
            return defaultPageSize
        }

        let targetWidth: CGFloat = 612
        let targetHeight = max(targetWidth * (normalizedSize.height / normalizedSize.width), 1)
        return CGSize(width: targetWidth, height: targetHeight)
    }
}
