import Combine
import Foundation
import PDFKit
import UIKit

struct PDFExportOptions {
    var fileName: String = ""
    var isCompressionEnabled = false
    var compressionPercent: Double = 35
    var isPasswordProtectionEnabled = false
    var password = ""
    var passwordConfirmation = ""

    var compressionQuality: CGFloat {
        let normalizedPercent = min(max(compressionPercent, 0), 100) / 100
        return CGFloat(max(0.12, 1.0 - normalizedPercent * 0.88))
    }

    func resolvedFileName(fallback: String) -> String {
        let trimmed = fileName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }
}

final class WorkflowController: ObservableObject {
    @Published private(set) var currentStep: WorkflowStep = .capture
    @Published private(set) var context: DocumentContext = .empty
    @Published private(set) var selectionState = SelectionState()
    @Published private(set) var captureStatusMessage = "Import a PDF, scan pages, or choose photos."
    @Published private(set) var isProcessingIntelligence = false
    @Published private(set) var intelligenceStatusMessage = "Ready to analyze."
    @Published private(set) var exportStatusMessage = "Ready to generate a PDF."
    @Published private(set) var lastExportedPDFURL: URL?
    @Published private(set) var lastExportedImageURLs: [URL] = []
    @Published private(set) var showsUndoDeleteBanner = false
    @Published private(set) var canUndoRestoreOriginal = false
    @Published private(set) var canUndoPreviewOperations = false
    @Published private(set) var canResetPreviewOperations = false
    @Published private(set) var lastDeletedPageDescription = ""
    @Published private(set) var lastRestoredPageID: UUID?
    @Published private(set) var shouldAutoLaunchScanner = false
    @Published private(set) var isApplyingPreviewEdit = false
    @Published var isShowingExportOptions = false
    @Published var exportOptions = PDFExportOptions()
    private var autoNamingEnabled = true
    private let intelligenceEngine = IntelligenceEngine()
    private let imageOptimizationService = ImageOptimizationService()
    private let pdfService = PDFService()
    private let fileStorageService = FileStorageService()
    private let ingestionService = DocumentIngestionService()
    private var lastDeletedPage: DeletedPageSnapshot?
    private var originalRestoreSnapshot: OriginalRestoreSnapshot?
    private var previewOperationHistory: [PreviewEditOperation] = []
    private var previousStepBeforeRecent: WorkflowStep = .capture

    func goToNextStep() {
        switch currentStep {
        case .launch:
            currentStep = .capture
            shouldAutoLaunchScanner = false
        case .capture:
            currentStep = .export
        case .export:
            currentStep = .viewer
        case .viewer:
            currentStep = .recent
        case .recent:
            currentStep = .capture
            shouldAutoLaunchScanner = true
        case .selection:
            endSelectionMode()
        }
    }

    func goToPreviousStep() {
        switch currentStep {
        case .launch:
            break
        case .capture:
            break
        case .export:
            currentStep = .capture
        case .viewer:
            currentStep = .export
        case .recent:
            currentStep = previousStepBeforeRecent
            shouldAutoLaunchScanner = false
        case .selection:
            endSelectionMode()
        }
    }

    func startSelectionMode() {
        guard context.pageCount > 0 else { return }
        selectionState.isMultiPageSelectionActive = true
        currentStep = .selection
    }

    func showRecentDocuments() {
        previousStepBeforeRecent = currentStep
        currentStep = .recent
    }

    func showCaptureShell() {
        currentStep = .capture
        shouldAutoLaunchScanner = false
    }

    func showViewer() {
        currentStep = .viewer
    }

    @discardableResult
    func openRecentDocument(_ item: RecentDocumentItem, password: String? = nil) -> DocumentImportError? {
        do {
            let imported = try ingestionService.importFile(from: item.fileURL, password: password)
            context.pages = imported.pages
            context.importSource = imported.source
            context.sourceFileURL = imported.sourceFileURL
            context.name = item.name
            context.detectedType = item.documentType
            context.extractedText = ""
            context.pdfData = try? Data(contentsOf: item.fileURL)
            selectionState.reset()
            context.selectedPages.removeAll()
            lastExportedPDFURL = item.fileURL
            lastExportedImageURLs = []
            exportStatusMessage = "PDF saved."
            currentStep = .viewer
            return nil
        } catch let error as DocumentImportError {
            exportStatusMessage = error.errorDescription ?? "Could not open saved PDF."
            currentStep = .recent
            return error
        } catch {
            exportStatusMessage = "Could not open saved PDF."
            currentStep = .recent
            return .unreadablePDF
        }
    }

    func showProtectedRecentDocument(_ item: RecentDocumentItem) {
        context.pages = []
        context.importSource = .filesPDF
        context.sourceFileURL = item.fileURL
        context.name = item.name
        context.detectedType = item.documentType
        context.extractedText = ""
        context.pdfData = try? Data(contentsOf: item.fileURL)
        selectionState.reset()
        context.selectedPages.removeAll()
        lastExportedPDFURL = item.fileURL
        lastExportedImageURLs = []
        exportStatusMessage = "PDF opened."
        currentStep = .viewer
    }

    func endSelectionMode() {
        selectionState.reset()
        currentStep = .viewer
        context.selectedPages.removeAll()
    }

    func resetDocument() {
        context = .empty
        selectionState.reset()
        captureStatusMessage = "Import a PDF, scan pages, or choose photos."
        exportStatusMessage = "Ready to generate a PDF."
        lastExportedPDFURL = nil
        lastExportedImageURLs = []
        lastDeletedPage = nil
        originalRestoreSnapshot = nil
        previewOperationHistory.removeAll()
        showsUndoDeleteBanner = false
        canUndoRestoreOriginal = false
        canUndoPreviewOperations = false
        canResetPreviewOperations = false
        lastRestoredPageID = nil
        currentStep = .capture
        shouldAutoLaunchScanner = true
    }

    func markAutoLaunchScannerHandled() {
        shouldAutoLaunchScanner = false
    }

    func setAutoNamingEnabled(_ enabled: Bool) {
        autoNamingEnabled = enabled
    }

    func setMode(_ mode: AppMode) {
        context.mode = mode
    }

    func replaceImages(_ images: [UIImage]) {
        context.pages = images.map { DocumentPage(image: $0, originalImage: $0, source: .sample) }
        clearDerivedOutput()
    }

    func appendImage(_ image: UIImage) {
        context.pages.append(DocumentPage(image: image, originalImage: image, source: .sample))
        clearDerivedOutput()
    }

    func insertPages(_ pages: [DocumentPage], afterPageID pageID: UUID?) {
        guard !pages.isEmpty else { return }

        var updatedPages = editableBasePages()

        if let pageID,
           let insertionAnchor = updatedPages.firstIndex(where: { $0.id == pageID }) {
            updatedPages.insert(contentsOf: pages, at: insertionAnchor + 1)
        } else {
            updatedPages.append(contentsOf: pages)
        }

        commitEditedPages(updatedPages, statusMessage: "Added \(pages.count) page\(pages.count == 1 ? "" : "s").")
        exportStatusMessage = "Added \(pages.count) page\(pages.count == 1 ? "" : "s")."
    }

    func removeImage(at index: Int) {
        var updatedPages = editableBasePages()
        guard updatedPages.indices.contains(index) else { return }
        let page = updatedPages[index]
        let previousPageID = index > 0 ? updatedPages[index - 1].id : nil
        let nextPageID = index + 1 < updatedPages.count ? updatedPages[index + 1].id : nil
        updatedPages.remove(at: index)
        let deletedSnapshot = DeletedPageSnapshot(
            page: page,
            index: index,
            previousPageID: previousPageID,
            nextPageID: nextPageID
        )
        lastDeletedPage = deletedSnapshot
        lastDeletedPageDescription = "Page \(index + 1) deleted."
        showsUndoDeleteBanner = true
        lastRestoredPageID = nil
        previewOperationHistory.append(.delete(snapshot: deletedSnapshot))
        refreshPreviewOperationState()
        deselectPage(index)
        commitEditedPages(updatedPages, statusMessage: "Page \(index + 1) deleted.")
    }

    func moveImage(fromOffsets source: IndexSet, toOffset destination: Int) {
        var updatedPages = editableBasePages()
        let moving = source.sorted().map { updatedPages[$0] }
        updatedPages.remove(atOffsets: source)
        updatedPages.insert(contentsOf: moving, at: max(0, min(destination, updatedPages.count)))
        commitEditedPages(updatedPages, statusMessage: "Reordered pages.")
    }

    func movePage(from sourceIndex: Int, to destinationIndex: Int) {
        var updatedPages = editableBasePages()
        guard updatedPages.indices.contains(sourceIndex),
              updatedPages.indices.contains(destinationIndex),
              sourceIndex != destinationIndex else { return }

        let page = updatedPages.remove(at: sourceIndex)
        updatedPages.insert(page, at: destinationIndex)
        commitEditedPages(updatedPages, statusMessage: "Reordered pages.")
    }

    func togglePageSelection(_ index: Int) {
        guard context.pages.indices.contains(index) else { return }

        if context.selectedPages.contains(index) {
            context.selectedPages.remove(index)
            selectionState.selectedPages.remove(index)
        } else {
            context.selectedPages.insert(index)
            selectionState.selectedPages.insert(index)
        }
    }

    func clearPageSelection() {
        context.selectedPages.removeAll()
        selectionState.selectedPages.removeAll()
    }

    func presentExportOptions() {
        exportOptions = PDFExportOptions(fileName: context.name)
        isShowingExportOptions = true
    }

    func dismissExportOptions() {
        isShowingExportOptions = false
    }

    func updateExtractedText(_ text: String) {
        context.extractedText = text
    }

    func updateDetectedType(_ type: DocumentType) {
        context.detectedType = type
        persistLibraryMetadataIfNeeded()
    }

    func updateName(_ name: String) {
        context.name = name
        persistLibraryMetadataIfNeeded()
    }

    func updatePDFData(_ data: Data?) {
        context.pdfData = data
    }

    func resetPreviewOperations() {
        guard !previewOperationHistory.isEmpty else { return }

        let basePages = editableBasePages()
        let operations = previewOperationHistory

        isApplyingPreviewEdit = true

        Task.detached(priority: .userInitiated) {
            var restoredPages = basePages
            var restoredPageID: UUID?

            for operation in operations.reversed() {
                switch operation {
                case .replaceImage(let pageID, let previousImage):
                    guard let index = restoredPages.firstIndex(where: { $0.id == pageID }) else { continue }
                    restoredPages[index].image = previousImage
                    restoredPageID = pageID
                case .delete(let snapshot):
                    restoredPages = Self.insertDeletedPage(snapshot, into: restoredPages)
                    restoredPageID = snapshot.page.id
                }
            }

            let committedRestoredPages = restoredPages
            let committedRestoredPageID = restoredPageID

            await MainActor.run {
                self.previewOperationHistory.removeAll()
                self.refreshPreviewOperationState()
                self.lastRestoredPageID = committedRestoredPageID
                self.context.pages = committedRestoredPages
                self.context.enhancementProfile = .none
                self.originalRestoreSnapshot = nil

                self.context.pdfData = nil
                self.context.extractedText = ""
                self.context.name = self.context.pages.isEmpty ? "Untitled Scan" : self.context.name
                self.intelligenceStatusMessage = "Ready to analyze."
                self.exportStatusMessage = "Reset edits."
                self.lastExportedPDFURL = nil
                self.lastExportedImageURLs = []
                self.isApplyingPreviewEdit = false
            }
        }
    }

    func replacePageImage(at index: Int, with image: UIImage) {
        var updatedPages = editableBasePages()
        guard updatedPages.indices.contains(index) else { return }
        let previousImage = updatedPages[index].image
        updatedPages[index].image = image
        previewOperationHistory.append(.replaceImage(pageID: updatedPages[index].id, previousImage: previousImage))
        refreshPreviewOperationState()
        commitEditedPages(updatedPages, statusMessage: "Updated page \(index + 1).")
        exportStatusMessage = "Updated page \(index + 1)."
    }

    func insertOverlayImage(_ overlay: UIImage, at index: Int, placement: InsertOverlayPlacement) {
        let basePages = editableBasePages()
        guard basePages.indices.contains(index) else { return }

        let targetPageID = basePages[index].id
        let previousImage = basePages[index].image

        isApplyingPreviewEdit = true

        Task.detached(priority: .userInitiated) {
            guard let composited = Self.makeCompositeImage(
                baseImage: previousImage,
                overlayImage: overlay,
                placement: placement
            ) else {
                await MainActor.run {
                    self.isApplyingPreviewEdit = false
                }
                return
            }

            var updatedPages = basePages
            updatedPages[index].image = composited
            let committedPages = updatedPages

            await MainActor.run {
                self.previewOperationHistory.append(.replaceImage(pageID: targetPageID, previousImage: previousImage))
                self.refreshPreviewOperationState()
                self.context.pages = committedPages
                self.context.enhancementProfile = .none
                self.originalRestoreSnapshot = nil
                self.context.pdfData = nil
                self.context.extractedText = ""
                self.intelligenceStatusMessage = "Ready to analyze."
                self.exportStatusMessage = "Updated page \(index + 1)."
                self.lastExportedPDFURL = nil
                self.lastExportedImageURLs = []
                self.isApplyingPreviewEdit = false
            }
        }
    }

    func rotatePage(at index: Int, clockwise: Bool = true) {
        let basePages = editableBasePages()
        guard basePages.indices.contains(index) else { return }

        let targetPageID = basePages[index].id
        let previousImage = basePages[index].image

        isApplyingPreviewEdit = true

        Task.detached(priority: .userInitiated) {
            var updatedPages = basePages
            guard let rotatedImage = previousImage.rotated90Degrees(clockwise: clockwise) else {
                await MainActor.run {
                    self.isApplyingPreviewEdit = false
                }
                return
            }

            updatedPages[index].image = rotatedImage

            let committedPages = updatedPages

            await MainActor.run {
                self.previewOperationHistory.append(.replaceImage(pageID: targetPageID, previousImage: previousImage))
                self.refreshPreviewOperationState()
                self.context.pages = committedPages
                self.context.enhancementProfile = .none
                self.originalRestoreSnapshot = nil

                self.context.pdfData = nil
                self.context.extractedText = ""
                self.context.name = self.context.pages.isEmpty ? "Untitled Scan" : self.context.name
                self.intelligenceStatusMessage = "Ready to analyze."
                self.exportStatusMessage = "Rotated page \(index + 1)."
                self.lastExportedPDFURL = nil
                self.lastExportedImageURLs = []
                self.isApplyingPreviewEdit = false
            }
        }
    }

    func duplicatePage(at index: Int) {
        var updatedPages = editableBasePages()
        guard updatedPages.indices.contains(index) else { return }
        let page = updatedPages[index]
        let duplicated = DocumentPage(
            image: page.image,
            originalImage: page.originalImage,
            source: page.source,
            sourcePageIndex: page.sourcePageIndex
        )
        updatedPages.insert(duplicated, at: index + 1)
        commitEditedPages(updatedPages, statusMessage: "Added a duplicate of page \(index + 1).")
        exportStatusMessage = "Added a duplicate of page \(index + 1)."
    }

    func restoreOriginalImages() {
        guard context.enhancementProfile != .none else { return }

        originalRestoreSnapshot = OriginalRestoreSnapshot(
            pages: context.pages,
            enhancementProfile: context.enhancementProfile
        )

        let restoredPages = context.pages.map { page -> DocumentPage in
            guard let originalImage = page.originalImage else { return page }
            var restoredPage = page
            restoredPage.image = originalImage
            return restoredPage
        }

        context.pages = restoredPages
        context.enhancementProfile = .none
        context.pdfData = nil
        canUndoRestoreOriginal = true
        exportStatusMessage = "Restored original scan."
    }

    func toggleAutoEnhancement() {
        if context.enhancementProfile != .none {
            if let originalRestoreSnapshot {
                context.pages = originalRestoreSnapshot.pages
                context.enhancementProfile = .none
                context.pdfData = nil
                canUndoRestoreOriginal = true
                exportStatusMessage = "Auto filter removed."
            } else {
                restoreOriginalImages()
            }
            return
        }

        if let originalRestoreSnapshot {
            let (optimizedPages, enhancementProfile) = imageOptimizationService.optimize(
                pages: originalRestoreSnapshot.pages,
                for: context.detectedType
            )
            context.pages = optimizedPages
            context.enhancementProfile = enhancementProfile
            context.pdfData = nil
            canUndoRestoreOriginal = true
            exportStatusMessage = "Auto filter applied."
            return
        }

        let (optimizedPages, enhancementProfile) = imageOptimizationService.optimize(
            pages: context.pages,
            for: context.detectedType
        )

        guard enhancementProfile != .none else {
            exportStatusMessage = "No auto filter available."
            return
        }

        originalRestoreSnapshot = OriginalRestoreSnapshot(
            pages: context.pages,
            enhancementProfile: enhancementProfile
        )
        context.pages = optimizedPages
        context.enhancementProfile = enhancementProfile
        context.pdfData = nil
        canUndoRestoreOriginal = true
        exportStatusMessage = "Auto filter applied."
    }

    func undoLastRefineAction() {
        if let lastOperation = previewOperationHistory.popLast() {
            var restoredPages = editableBasePages()

            switch lastOperation {
            case .replaceImage(let pageID, let previousImage):
                guard let index = restoredPages.firstIndex(where: { $0.id == pageID }) else {
                    refreshPreviewOperationState()
                    return
                }
                restoredPages[index].image = previousImage
                lastRestoredPageID = pageID
                commitEditedPages(restoredPages, statusMessage: "Reverted last edit.")
            case .delete(let snapshot):
                restoredPages = Self.insertDeletedPage(snapshot, into: restoredPages)
                lastRestoredPageID = snapshot.page.id
                commitEditedPages(restoredPages, statusMessage: "Restored deleted page.")
            }

            refreshPreviewOperationState()
            return
        }

        if let originalRestoreSnapshot {
            context.pages = originalRestoreSnapshot.pages
            context.enhancementProfile = originalRestoreSnapshot.enhancementProfile
            context.pdfData = nil
            self.originalRestoreSnapshot = nil
            canUndoRestoreOriginal = false
            exportStatusMessage = "Restored optimized version."
            return
        }

        restoreLastDeletedPage()
    }

    func restoreLastDeletedPage() {
        guard let lastDeletedPage else { return }
        var updatedPages = editableBasePages()
        updatedPages = Self.insertDeletedPage(lastDeletedPage, into: updatedPages)
        lastRestoredPageID = lastDeletedPage.page.id
        self.lastDeletedPage = nil
        showsUndoDeleteBanner = false
        lastDeletedPageDescription = ""
        commitEditedPages(updatedPages, statusMessage: "Restored deleted page.")
    }

    func dismissUndoBanner() {
        lastDeletedPage = nil
        showsUndoDeleteBanner = false
        lastRestoredPageID = nil
    }

    func generatePDFIfNeeded() {
        guard !context.pages.isEmpty else {
            exportStatusMessage = "Add pages before exporting."
            return
        }

        if let existingPDF = context.pdfData, !existingPDF.isEmpty {
            exportStatusMessage = "PDF ready."
            return
        }

        context.pdfData = pdfService.createPDFData(from: context.images)
        exportStatusMessage = context.pdfData == nil ? "Unable to generate PDF." : "PDF generated."
    }

    @MainActor
    func regeneratePDFPreview() async {
        guard !context.pages.isEmpty else {
            context.pdfData = nil
            exportStatusMessage = "Add pages before exporting."
            return
        }

        let snapshot = previewFingerprint(for: context.pages)
        let images = context.images
        let service = pdfService

        let regeneratedPDF = await Task.detached(priority: .userInitiated) {
            service.createPDFData(from: images)
        }.value

        guard snapshot == previewFingerprint(for: context.pages) else { return }

        context.pdfData = regeneratedPDF
        exportStatusMessage = regeneratedPDF == nil ? "Unable to generate PDF." : "PDF ready."
    }

    func exportCurrentPDF() {
        generatePDFIfNeeded()

        guard let pdfData = context.pdfData else { return }

        do {
            lastExportedPDFURL = try fileStorageService.save(documentData: pdfData, named: context.name)
            if let lastExportedPDFURL {
                context.sourceFileURL = lastExportedPDFURL
                fileStorageService.upsertDocumentMetadata(
                    for: lastExportedPDFURL,
                    name: context.name,
                    documentType: context.detectedType,
                    pageCount: context.pageCount
                )
            }
            exportStatusMessage = "Saved to Documents."
        } catch {
            exportStatusMessage = "Saving PDF failed: \(error.localizedDescription)"
        }
    }

    func savePDF(using options: PDFExportOptions, showRecentAfterSave: Bool = true) {
        let resolvedName = options.resolvedFileName(fallback: context.name)
        let sourceImages = context.images
        guard !sourceImages.isEmpty else {
            exportStatusMessage = "No pages available to save."
            return
        }

        let compressionQuality = options.isCompressionEnabled ? options.compressionQuality : nil
        guard let generatedPDF = pdfService.createPDFData(from: sourceImages, compressionQuality: compressionQuality) else {
            exportStatusMessage = "Could not generate the PDF."
            return
        }

        let finalPDF: Data
        if options.isPasswordProtectionEnabled {
            guard let protectedPDF = pdfService.passwordProtectedPDFData(
                from: generatedPDF,
                userPassword: options.password
            ) else {
                exportStatusMessage = "Could not protect the PDF."
                return
            }
            finalPDF = protectedPDF
        } else {
            finalPDF = generatedPDF
        }

        do {
            let savedURL = try fileStorageService.save(documentData: finalPDF, named: resolvedName)
            fileStorageService.upsertDocumentMetadata(
                for: savedURL,
                name: resolvedName,
                documentType: context.detectedType,
                pageCount: context.pageCount
            )

            context.name = resolvedName
            context.pdfData = finalPDF
            context.sourceFileURL = savedURL
            lastExportedPDFURL = savedURL
            isShowingExportOptions = false
            exportStatusMessage = exportSuccessMessage(for: options)

            if showRecentAfterSave {
                showRecentDocuments()
            }
        } catch {
            exportStatusMessage = "Saving PDF failed: \(error.localizedDescription)"
        }
    }

    func savePDFAndOpenViewer() {
        exportCurrentPDF()
        guard lastExportedPDFURL != nil else { return }
        currentStep = .viewer
    }

    func savePDFAndShowRecent() {
        exportCurrentPDF()
        guard lastExportedPDFURL != nil else { return }
        showRecentDocuments()
    }

    func exportCurrentPagesAsImages() {
        let imageData = pdfService.exportImages(from: context.images)
        guard !imageData.isEmpty else {
            exportStatusMessage = "No pages available for image export."
            return
        }

        do {
            lastExportedImageURLs = try fileStorageService.save(images: imageData, named: context.name)
            exportStatusMessage = "Images saved."
        } catch {
            exportStatusMessage = "Saving images failed: \(error.localizedDescription)"
        }
    }

    func createDocumentFromSelection(named proposedName: String? = nil) {
        guard !context.selectedPages.isEmpty else {
            exportStatusMessage = "Select pages before extracting a new PDF."
            return
        }

        generatePDFIfNeeded()
        guard let pdfData = context.pdfData,
              let selectedPDF = pdfService.extractSelectedPages(from: pdfData, pages: context.selectedPages) else {
            exportStatusMessage = "Could not extract the selected pages."
            return
        }

        let selectedIndexes = context.selectedPages.sorted()
        context.pages = selectedIndexes.compactMap { context.pages.indices.contains($0) ? context.pages[$0] : nil }
        let trimmedName = proposedName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmedName.isEmpty {
            context.name = trimmedName
        }
        context.pdfData = selectedPDF
        selectionState.reset()
        context.selectedPages.removeAll()
        exportCurrentPDF()
        currentStep = .viewer
        exportStatusMessage = lastExportedPDFURL == nil ? "Split created." : "Split saved."
    }

    func removeSelectedPages() {
        guard !context.selectedPages.isEmpty else {
            exportStatusMessage = "Select pages before removing them."
            return
        }

        let wasInSelectionMode = currentStep == .selection
        let selectedIndexes = context.selectedPages
        context.pages = context.pages.enumerated().compactMap { index, page in
            selectedIndexes.contains(index) ? nil : page
        }
        selectionState.reset()
        context.selectedPages.removeAll()
        context.pdfData = context.pages.isEmpty ? nil : pdfService.createPDFData(from: context.images)

        if context.pages.isEmpty {
            if let sourceFileURL = context.sourceFileURL {
                try? fileStorageService.deleteDocument(at: sourceFileURL)
            }
            lastExportedPDFURL = nil
            exportStatusMessage = "Document deleted."
            showRecentDocuments()
            return
        }

        persistCurrentDocumentIfNeeded()
        exportStatusMessage = "Removed selected pages."
        currentStep = wasInSelectionMode ? .selection : .viewer
    }

    func createDocumentRemovingSelection(named proposedName: String? = nil) {
        guard !context.selectedPages.isEmpty else {
            exportStatusMessage = "Select pages before removing them."
            return
        }

        generatePDFIfNeeded()
        guard let pdfData = context.pdfData,
              let revisedPDF = pdfService.removeSelectedPages(from: pdfData, pages: context.selectedPages) else {
            exportStatusMessage = "Could not create the revised PDF."
            return
        }

        let remainingPages = context.pages.enumerated().compactMap { index, page in
            context.selectedPages.contains(index) ? nil : page
        }

        guard !remainingPages.isEmpty else {
            exportStatusMessage = "Select fewer pages to save a revised PDF."
            return
        }

        let trimmedName = proposedName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let baseName = context.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let revisedName = trimmedName.isEmpty
            ? (baseName.isEmpty ? "Revised PDF" : "\(baseName) Revised")
            : trimmedName

        do {
            let savedURL = try fileStorageService.save(documentData: revisedPDF, named: revisedName)
            fileStorageService.upsertDocumentMetadata(
                for: savedURL,
                name: revisedName,
                documentType: context.detectedType,
                pageCount: remainingPages.count
            )

            context.pages = remainingPages
            context.name = revisedName
            context.pdfData = revisedPDF
            context.sourceFileURL = savedURL
            selectionState.reset()
            context.selectedPages.removeAll()
            lastExportedPDFURL = savedURL
            exportStatusMessage = "Revised PDF saved."
            currentStep = .viewer
        } catch {
            exportStatusMessage = "Saving revised PDF failed: \(error.localizedDescription)"
        }
    }

    func createDocumentReorderingPages(_ reorderedPages: [DocumentPage], named proposedName: String? = nil) {
        guard !reorderedPages.isEmpty else {
            exportStatusMessage = "Reorder at least one page before saving."
            return
        }

        let reorderedPDF = pdfService.createPDFData(from: reorderedPages.map(\.image))
        guard let reorderedPDF else {
            exportStatusMessage = "Could not create the reordered PDF."
            return
        }

        let trimmedName = proposedName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let baseName = context.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let reorderedName = trimmedName.isEmpty
            ? (baseName.isEmpty ? "Reordered PDF" : "\(baseName) Reordered")
            : trimmedName

        do {
            let savedURL = try fileStorageService.save(documentData: reorderedPDF, named: reorderedName)
            fileStorageService.upsertDocumentMetadata(
                for: savedURL,
                name: reorderedName,
                documentType: context.detectedType,
                pageCount: reorderedPages.count
            )

            context.pages = reorderedPages
            context.name = reorderedName
            context.pdfData = reorderedPDF
            context.sourceFileURL = savedURL
            context.selectedPages.removeAll()
            selectionState.reset()
            lastExportedPDFURL = savedURL
            exportStatusMessage = "Reordered PDF saved."
            currentStep = .viewer
        } catch {
            exportStatusMessage = "Saving reordered PDF failed: \(error.localizedDescription)"
        }
    }

    func mergeCurrentDocumentWithItselfForDemo() {
        generatePDFIfNeeded()
        guard let pdfData = context.pdfData,
              let mergedPDF = pdfService.merge(pdfDataItems: [pdfData, pdfData]) else {
            exportStatusMessage = "Could not merge the current PDF."
            return
        }

        let duplicatePages = context.pages.enumerated().map { index, page in
            DocumentPage(
                image: page.image,
                originalImage: page.originalImage,
                source: page.source,
                sourcePageIndex: context.pageCount + index
            )
        }
        context.pages.append(contentsOf: duplicatePages)
        context.pdfData = mergedPDF
        exportStatusMessage = "Merged copy ready."
        currentStep = .launch
    }

    func ingest(_ importedDocument: ImportedDocument) {
        context.pages = importedDocument.pages
        context.importSource = importedDocument.source
        context.sourceFileURL = importedDocument.sourceFileURL
        if let sourceFileURL = importedDocument.sourceFileURL {
            context.name = sourceFileURL.deletingPathExtension().lastPathComponent
        } else {
            context.name = "Untitled Scan"
        }
        selectionState.reset()
        context.selectedPages.removeAll()
        clearDerivedOutput()
        captureStatusMessage = "Imported \(context.pageCount) page\(context.pageCount == 1 ? "" : "s")."
        intelligenceStatusMessage = "Ready to analyze imported content."
        currentStep = .export
        shouldAutoLaunchScanner = false

        Task {
            await runIntelligenceIfNeeded()
        }
    }

    func updateCaptureStatus(_ message: String) {
        captureStatusMessage = message
    }

    @MainActor
    func runIntelligenceIfNeeded() async {
        guard !context.pages.isEmpty else {
            intelligenceStatusMessage = "Add a document before running analysis."
            return
        }

        guard !isProcessingIntelligence else { return }

        isProcessingIntelligence = true
        intelligenceStatusMessage = "Running OCR and document understanding..."

        let analyzedContext = await intelligenceEngine.process(
            context: context,
            autoNamingEnabled: autoNamingEnabled
        )
        context = applyAutoEnhancement(to: analyzedContext)
        previewOperationHistory.removeAll()
        refreshPreviewOperationState()
        isProcessingIntelligence = false
        intelligenceStatusMessage = context.enhancementProfile == .none
            ? "Ready to edit."
            : context.enhancementProfile.displayTitle

        if currentStep == .export || currentStep == .viewer {
            generatePDFIfNeeded()
        }
    }

    private func clearDerivedOutput() {
        context.pdfData = nil
        context.extractedText = ""
        context.name = context.pages.isEmpty ? "Untitled Scan" : context.name
        context.detectedType = .general
        context.enhancementProfile = .none
        originalRestoreSnapshot = nil
        previewOperationHistory.removeAll()
        canUndoRestoreOriginal = false
        canUndoPreviewOperations = false
        canResetPreviewOperations = false
        intelligenceStatusMessage = "Ready to analyze."
        exportStatusMessage = "Ready to generate a PDF."
        lastExportedPDFURL = nil
        lastExportedImageURLs = []
    }

    private func exportSuccessMessage(for options: PDFExportOptions) -> String {
        switch (options.isCompressionEnabled, options.isPasswordProtectionEnabled) {
        case (true, true):
            return "Protected and compressed PDF saved to Documents."
        case (true, false):
            return "Compressed PDF saved to Documents."
        case (false, true):
            return "Protected PDF saved to Documents."
        case (false, false):
            return "PDF saved to Documents."
        }
    }

    private func applyAutoEnhancement(to analyzedContext: DocumentContext) -> DocumentContext {
        let (optimizedPages, enhancementProfile) = imageOptimizationService.optimize(
            pages: analyzedContext.pages,
            for: analyzedContext.detectedType
        )

        guard enhancementProfile != .none else {
            originalRestoreSnapshot = nil
            canUndoRestoreOriginal = false
            return analyzedContext
        }

        var updatedContext = analyzedContext
        updatedContext.pages = optimizedPages
        updatedContext.enhancementProfile = enhancementProfile
        updatedContext.pdfData = nil
        originalRestoreSnapshot = OriginalRestoreSnapshot(
            pages: analyzedContext.pages,
            enhancementProfile: enhancementProfile
        )
        canUndoRestoreOriginal = false
        return updatedContext
    }

    private func editableBasePages() -> [DocumentPage] {
        if context.enhancementProfile != .none, let originalRestoreSnapshot {
            return originalRestoreSnapshot.pages
        }

        return context.pages
    }

    private func commitEditedPages(_ pages: [DocumentPage], statusMessage: String) {
        context.pages = pages
        context.enhancementProfile = .none
        originalRestoreSnapshot = nil

        context.pdfData = nil
        context.extractedText = ""
        context.name = context.pages.isEmpty ? "Untitled Scan" : context.name
        intelligenceStatusMessage = "Ready to analyze."
        exportStatusMessage = statusMessage
        lastExportedPDFURL = nil
        lastExportedImageURLs = []
    }

    private func refreshPreviewOperationState() {
        canUndoPreviewOperations = !previewOperationHistory.isEmpty
        canResetPreviewOperations = !previewOperationHistory.isEmpty

        if let lastDelete = previewOperationHistory.reversed().compactMap({
            if case let .delete(snapshot) = $0 { return snapshot }
            return nil
        }).first {
            lastDeletedPage = lastDelete
            showsUndoDeleteBanner = true
            lastDeletedPageDescription = "Page deleted."
        } else {
            lastDeletedPage = nil
            showsUndoDeleteBanner = false
            lastDeletedPageDescription = ""
        }
    }

    private static func insertDeletedPage(_ snapshot: DeletedPageSnapshot, into pages: [DocumentPage]) -> [DocumentPage] {
        var updatedPages = pages

        if let nextPageID = snapshot.nextPageID,
           let nextIndex = updatedPages.firstIndex(where: { $0.id == nextPageID }) {
            updatedPages.insert(snapshot.page, at: nextIndex)
            return updatedPages
        }

        if let previousPageID = snapshot.previousPageID,
           let previousIndex = updatedPages.firstIndex(where: { $0.id == previousPageID }) {
            updatedPages.insert(snapshot.page, at: previousIndex + 1)
            return updatedPages
        }

        let insertionIndex = min(snapshot.index, updatedPages.count)
        updatedPages.insert(snapshot.page, at: insertionIndex)
        return updatedPages
    }

    private static func makeCompositeImage(
        baseImage: UIImage,
        overlayImage: UIImage,
        placement: InsertOverlayPlacement
    ) -> UIImage? {
        let size = baseImage.size
        guard size.width > 0, size.height > 0 else { return nil }

        let rendererFormat = UIGraphicsImageRendererFormat.default()
        rendererFormat.scale = baseImage.scale
        rendererFormat.opaque = true

        let renderer = UIGraphicsImageRenderer(size: size, format: rendererFormat)
        return renderer.image { context in
            baseImage.draw(in: CGRect(origin: .zero, size: size))

            let overlaySize = CGSize(
                width: max(1, placement.normalizedSize.width * size.width),
                height: max(1, placement.normalizedSize.height * size.height)
            )
            let center = CGPoint(
                x: placement.normalizedCenter.x * size.width,
                y: placement.normalizedCenter.y * size.height
            )

            let cgContext = context.cgContext
            cgContext.saveGState()
            cgContext.translateBy(x: center.x, y: center.y)
            cgContext.rotate(by: placement.rotationRadians)
            overlayImage.draw(
                in: CGRect(
                    x: -overlaySize.width / 2,
                    y: -overlaySize.height / 2,
                    width: overlaySize.width,
                    height: overlaySize.height
                )
            )
            cgContext.restoreGState()
        }
    }

    private func persistLibraryMetadataIfNeeded() {
        let targetURL = context.sourceFileURL ?? lastExportedPDFURL
        guard let targetURL, targetURL.pathExtension.lowercased() == "pdf" else { return }

        fileStorageService.upsertDocumentMetadata(
            for: targetURL,
            name: context.name,
            documentType: context.detectedType,
            pageCount: context.pageCount
        )
    }

    private func persistCurrentDocumentIfNeeded() {
        guard let sourceFileURL = context.sourceFileURL,
              sourceFileURL.pathExtension.lowercased() == "pdf",
              let pdfData = context.pdfData else {
            return
        }

        do {
            try pdfData.write(to: sourceFileURL, options: .atomic)
            lastExportedPDFURL = sourceFileURL
            persistLibraryMetadataIfNeeded()
        } catch {
            exportStatusMessage = "Could not update saved document."
        }
    }

    private func previewFingerprint(for pages: [DocumentPage]) -> Int {
        var hasher = Hasher()

        for page in pages {
            hasher.combine(page.id)
            hasher.combine(page.image.size.width)
            hasher.combine(page.image.size.height)
        }

        return hasher.finalize()
    }

    private func deselectPage(_ index: Int) {
        context.selectedPages.remove(index)
        selectionState.selectedPages.remove(index)
    }
}

private struct DeletedPageSnapshot {
    let page: DocumentPage
    let index: Int
    let previousPageID: UUID?
    let nextPageID: UUID?
}

private struct OriginalRestoreSnapshot {
    let pages: [DocumentPage]
    let enhancementProfile: EnhancementProfile
}

private enum PreviewEditOperation {
    case replaceImage(pageID: UUID, previousImage: UIImage)
    case delete(snapshot: DeletedPageSnapshot)
}

private extension Array {
    mutating func remove(atOffsets offsets: IndexSet) {
        for index in offsets.sorted(by: >) {
            remove(at: index)
        }
    }
}

private extension UIImage {
    func rotated90Degrees(clockwise: Bool) -> UIImage? {
        let angle = clockwise ? CGFloat.pi / 2 : -CGFloat.pi / 2
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size.height, height: size.width))

        return renderer.image { context in
            let cgContext = context.cgContext
            cgContext.translateBy(x: renderer.format.bounds.midX, y: renderer.format.bounds.midY)
            cgContext.rotate(by: angle)
            draw(in: CGRect(x: -size.width / 2, y: -size.height / 2, width: size.width, height: size.height))
        }
    }
}
