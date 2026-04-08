import Foundation
import UIKit

final class IntelligenceEngine {
    var ocrService = OCRService()
    var typeDetector = DocumentTypeDetector()
    var entityExtractor = EntityExtractionService()
    var namingService = SmartNamingService()
    private var cachedFingerprint: Int?
    private var cachedResult: DocumentContext?

    func process(context: DocumentContext, autoNamingEnabled: Bool) async -> DocumentContext {
        let fingerprint = cacheFingerprint(for: context)

        if let cachedFingerprint, cachedFingerprint == fingerprint, let cachedResult {
            var hydratedResult = cachedResult
            hydratedResult.pages = context.pages
            hydratedResult.mode = context.mode
            hydratedResult.importSource = context.importSource
            hydratedResult.sourceFileURL = context.sourceFileURL
            return hydratedResult
        }

        let images = context.images
        let ocrResult = await ocrService.recognizeText(in: images)
        let documentType = typeDetector.detectType(from: ocrResult.fullText)
        let entities = entityExtractor.extract(from: ocrResult.fullText)
        let name: String
        if autoNamingEnabled {
            name = namingService.makeName(for: documentType, entities: entities, mode: context.mode)
        } else if let sourceFileURL = context.sourceFileURL {
            name = sourceFileURL.deletingPathExtension().lastPathComponent
        } else {
            name = "Untitled Scan"
        }
        let result = DocumentContext(
            id: context.id,
            pages: context.pages,
            pdfData: context.pdfData,
            detectedType: documentType,
            extractedText: ocrResult.fullText,
            name: name,
            mode: context.mode,
            selectedPages: context.selectedPages,
            isPremiumLocked: context.isPremiumLocked,
            importSource: context.importSource,
            sourceFileURL: context.sourceFileURL
        )

        cachedFingerprint = fingerprint
        cachedResult = result
        return result
    }

    private func cacheFingerprint(for context: DocumentContext) -> Int {
        var hasher = Hasher()
        hasher.combine(context.pageCount)
        hasher.combine(context.mode.rawValue)

        for page in context.pages {
            hasher.combine(page.id)
            hasher.combine(page.image.size.width)
            hasher.combine(page.image.size.height)
            hasher.combine(page.source.rawValue)
        }

        return hasher.finalize()
    }
}
