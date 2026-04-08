import UIKit
import XCTest
import PDFKit

@testable import ScanovaApp

final class ScanovaAppTests: XCTestCase {
    func testInsertPagesAfterAnchorInsertsAtExpectedPosition() throws {
        let controller = WorkflowController()
        controller.replaceImages([makeImage(.red), makeImage(.blue)])

        let anchorID = try XCTUnwrap(controller.context.pages.first?.id)
        let trailingID = try XCTUnwrap(controller.context.pages.last?.id)
        let insertedPage = DocumentPage(
            image: makeImage(.green),
            originalImage: makeImage(.green),
            source: .sample
        )

        controller.updatePDFData(Data([0x01]))
        controller.insertPages([insertedPage], afterPageID: anchorID)

        XCTAssertEqual(controller.context.pages.map(\.id), [anchorID, insertedPage.id, trailingID])
        XCTAssertNil(controller.context.pdfData)
        XCTAssertEqual(controller.exportStatusMessage, "Added 1 page.")
    }

    func testUndoLastRefineActionRestoresDeletedPage() throws {
        let controller = WorkflowController()
        controller.replaceImages([makeImage(.red), makeImage(.blue), makeImage(.green)])

        let deletedPageID = try XCTUnwrap(controller.context.pages[1].id)

        controller.removeImage(at: 1)

        XCTAssertEqual(controller.context.pageCount, 2)
        XCTAssertTrue(controller.canUndoPreviewOperations)
        XCTAssertTrue(controller.canResetPreviewOperations)
        XCTAssertTrue(controller.showsUndoDeleteBanner)

        controller.undoLastRefineAction()

        XCTAssertEqual(controller.context.pageCount, 3)
        XCTAssertFalse(controller.canUndoPreviewOperations)
        XCTAssertFalse(controller.canResetPreviewOperations)
        XCTAssertEqual(controller.lastRestoredPageID, deletedPageID)
    }

    func testResetPreviewOperationsRestoresOriginalPages() async {
        let controller = WorkflowController()
        let originalFirstImage = makeImage(.red)
        controller.replaceImages([originalFirstImage, makeImage(.blue)])

        controller.replacePageImage(at: 0, with: makeImage(.purple))
        controller.removeImage(at: 1)
        controller.resetPreviewOperations()

        for _ in 0..<60 where controller.isApplyingPreviewEdit {
            try? await Task.sleep(for: .milliseconds(20))
        }

        XCTAssertFalse(controller.isApplyingPreviewEdit)
        XCTAssertEqual(controller.context.pageCount, 2)
        XCTAssertEqual(controller.context.pages.first?.image.pngData(), originalFirstImage.pngData())
        XCTAssertFalse(controller.canUndoPreviewOperations)
        XCTAssertFalse(controller.canResetPreviewOperations)
        XCTAssertEqual(controller.exportStatusMessage, "Reset edits.")
    }

    func testCreateDocumentFromSelectionTrimsNameAndSavesSelectedPages() {
        let controller = WorkflowController()
        controller.replaceImages([makeImage(.red), makeImage(.blue), makeImage(.green)])

        controller.togglePageSelection(0)
        controller.togglePageSelection(2)
        controller.createDocumentFromSelection(named: "  Custom Split  ")

        let savedURL = controller.lastExportedPDFURL
        defer { removeItemIfNeeded(at: savedURL) }

        XCTAssertEqual(controller.context.pageCount, 2)
        XCTAssertEqual(controller.context.name, "Custom Split")
        XCTAssertEqual(controller.currentStep, .viewer)
        XCTAssertTrue(controller.context.selectedPages.isEmpty)
        XCTAssertTrue(controller.selectionState.selectedPages.isEmpty)
        XCTAssertNotNil(savedURL)
        XCTAssertEqual(savedURL?.pathExtension.lowercased(), "pdf")
        XCTAssertTrue(savedURL.map { FileManager.default.fileExists(atPath: $0.path) } ?? false)
        XCTAssertEqual(controller.exportStatusMessage, "Split saved.")
    }

    func testCreateDocumentRemovingSelectionUsesRevisedFallbackAndKeepsOriginalFile() {
        let controller = WorkflowController()
        controller.replaceImages([makeImage(.red), makeImage(.blue), makeImage(.green)])
        controller.updateName("Trip Notes")
        controller.exportCurrentPDF()

        let originalURL = controller.lastExportedPDFURL
        XCTAssertNotNil(originalURL)

        controller.togglePageSelection(1)
        controller.createDocumentRemovingSelection(named: "   ")

        let revisedURL = controller.lastExportedPDFURL
        defer {
            removeItemIfNeeded(at: revisedURL)
            removeItemIfNeeded(at: originalURL)
        }

        XCTAssertEqual(controller.context.pageCount, 2)
        XCTAssertEqual(controller.context.name, "Trip Notes Revised")
        XCTAssertEqual(controller.currentStep, .viewer)
        XCTAssertTrue(controller.context.selectedPages.isEmpty)
        XCTAssertTrue(controller.selectionState.selectedPages.isEmpty)
        XCTAssertNotNil(revisedURL)
        XCTAssertNotEqual(revisedURL, originalURL)
        XCTAssertTrue(originalURL.map { FileManager.default.fileExists(atPath: $0.path) } ?? false)
        XCTAssertTrue(revisedURL.map { FileManager.default.fileExists(atPath: $0.path) } ?? false)
        XCTAssertEqual(controller.exportStatusMessage, "Revised PDF saved.")
    }

    func testCreateDocumentReorderingPagesUsesFallbackAndKeepsOriginalFile() throws {
        let controller = WorkflowController()
        controller.replaceImages([makeImage(.red), makeImage(.blue), makeImage(.green)])
        controller.updateName("Session Notes")
        controller.exportCurrentPDF()

        let originalURL = try XCTUnwrap(controller.lastExportedPDFURL)
        let reorderedPages = [controller.context.pages[2], controller.context.pages[0], controller.context.pages[1]]

        controller.createDocumentReorderingPages(reorderedPages, named: "   ")

        let reorderedURL = controller.lastExportedPDFURL
        defer {
            removeItemIfNeeded(at: reorderedURL)
            removeItemIfNeeded(at: originalURL)
        }

        XCTAssertEqual(controller.context.name, "Session Notes Reordered")
        XCTAssertEqual(controller.context.pages.map(\.id), reorderedPages.map(\.id))
        XCTAssertEqual(controller.currentStep, .viewer)
        XCTAssertNotNil(reorderedURL)
        XCTAssertNotEqual(reorderedURL, originalURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: originalURL.path))
        XCTAssertTrue(reorderedURL.map { FileManager.default.fileExists(atPath: $0.path) } ?? false)
        XCTAssertEqual(controller.exportStatusMessage, "Reordered PDF saved.")
    }

    func testInsertOverlayImageFlattensIntoPageAndCanBeReset() async {
        let controller = WorkflowController()
        let originalImage = makeImage(.white, size: CGSize(width: 220, height: 300))
        controller.replaceImages([originalImage])

        let overlay = InsertShapeConfiguration(
            kind: .rectangle,
            color: .red,
            strokeWidth: .medium,
            isFilled: true
        ).makeOverlayImage()

        controller.insertOverlayImage(overlay, at: 0, placement: .centered)

        for _ in 0..<60 where controller.isApplyingPreviewEdit {
            try? await Task.sleep(for: .milliseconds(20))
        }

        XCTAssertNotEqual(controller.context.pages[0].image.pngData(), originalImage.pngData())
        XCTAssertTrue(controller.canResetPreviewOperations)

        controller.resetPreviewOperations()

        for _ in 0..<60 where controller.isApplyingPreviewEdit {
            try? await Task.sleep(for: .milliseconds(20))
        }

        XCTAssertEqual(controller.context.pages[0].image.pngData(), originalImage.pngData())
    }

    func testSavePDFUsingCompressionSavesConfiguredCopy() throws {
        let controller = WorkflowController()
        controller.replaceImages([makeImage(.red), makeImage(.blue), makeImage(.green)])
        controller.updateName("Workshop Notes")

        var options = PDFExportOptions(fileName: "Workshop Notes", isCompressionEnabled: true)
        options.compressionPercent = 82
        controller.savePDF(using: options, showRecentAfterSave: false)

        let savedURL = try XCTUnwrap(controller.lastExportedPDFURL)
        defer { removeItemIfNeeded(at: savedURL) }

        XCTAssertEqual(controller.context.name, "Workshop Notes")
        XCTAssertEqual(controller.exportStatusMessage, "Compressed PDF saved to Documents.")
        XCTAssertTrue(FileManager.default.fileExists(atPath: savedURL.path))
    }

    func testSaveProtectedPDFCreatesLockedFileAndReopensWithPassword() throws {
        let controller = WorkflowController()
        let fileStorageService = FileStorageService()
        controller.replaceImages([makeImage(.red), makeImage(.blue)])
        controller.updateName("Protected Notes")

        var options = PDFExportOptions(fileName: "Protected Notes", isPasswordProtectionEnabled: true)
        options.password = "1234"
        options.passwordConfirmation = "1234"
        controller.savePDF(using: options, showRecentAfterSave: false)

        let savedURL = try XCTUnwrap(controller.lastExportedPDFURL)
        defer { deleteDocumentIfNeeded(at: savedURL, using: fileStorageService) }

        let protectedDocument = try XCTUnwrap(PDFDocument(url: savedURL))
        XCTAssertTrue(protectedDocument.isLocked)
        XCTAssertEqual(controller.exportStatusMessage, "Protected PDF saved to Documents.")

        let item = try XCTUnwrap(
            fileStorageService.listRecentDocuments().first(where: { $0.fileURL == savedURL })
        )

        let lockedOpenController = WorkflowController()
        let passwordRequired = lockedOpenController.openRecentDocument(item)
        if case .passwordRequired? = passwordRequired {
        } else {
            XCTFail("Expected passwordRequired when opening protected PDF without a password.")
        }

        let unlockedOpenController = WorkflowController()
        let unlockError = unlockedOpenController.openRecentDocument(item, password: "1234")
        XCTAssertNil(unlockError)
        XCTAssertEqual(unlockedOpenController.currentStep, .viewer)
        XCTAssertEqual(unlockedOpenController.context.name, "Protected Notes")
        XCTAssertEqual(unlockedOpenController.context.pageCount, 2)
    }

    func testMergeCurrentDocumentWithItselfForDemoDoublesPagesAndKeepsPreviewState() throws {
        let controller = WorkflowController()
        controller.replaceImages([makeImage(.red), makeImage(.blue)])

        XCTAssertNil(controller.context.pdfData)

        controller.mergeCurrentDocumentWithItselfForDemo()

        XCTAssertEqual(controller.context.pageCount, 4)
        XCTAssertNotNil(controller.context.pdfData)
        XCTAssertEqual(controller.exportStatusMessage, "Merged copy ready.")
        XCTAssertEqual(controller.currentStep, .launch)
    }

    func testListRecentDocumentsUsesStoredMetadataForSavedPDF() {
        let controller = WorkflowController()
        let fileStorageService = FileStorageService()
        let uniqueName = "Library Test \(UUID().uuidString)"

        controller.replaceImages([makeImage(.red), makeImage(.blue)])
        controller.updateName(uniqueName)
        controller.updateDetectedType(.invoice)
        controller.exportCurrentPDF()

        let savedURL = controller.lastExportedPDFURL
        defer { deleteDocumentIfNeeded(at: savedURL, using: fileStorageService) }

        let recentItem = fileStorageService.listRecentDocuments().first(where: { $0.fileURL == savedURL })

        XCTAssertEqual(recentItem?.name, uniqueName)
        XCTAssertEqual(recentItem?.documentType, .invoice)
        XCTAssertEqual(recentItem?.pageCount, 2)
    }

    func testOpenRecentDocumentLoadsViewerStateFromSavedPDF() throws {
        let saveController = WorkflowController()
        let fileStorageService = FileStorageService()
        let uniqueName = "Open Recent \(UUID().uuidString)"

        saveController.replaceImages([makeImage(.red), makeImage(.blue), makeImage(.green)])
        saveController.updateName(uniqueName)
        saveController.updateDetectedType(.receipt)
        saveController.exportCurrentPDF()

        let savedURL = try XCTUnwrap(saveController.lastExportedPDFURL)
        defer { deleteDocumentIfNeeded(at: savedURL, using: fileStorageService) }

        let recentItem = try XCTUnwrap(
            fileStorageService.listRecentDocuments().first(where: { $0.fileURL == savedURL })
        )

        let openController = WorkflowController()
        openController.openRecentDocument(recentItem)

        XCTAssertEqual(openController.currentStep, .viewer)
        XCTAssertEqual(openController.context.name, uniqueName)
        XCTAssertEqual(openController.context.detectedType, .receipt)
        XCTAssertEqual(openController.context.pageCount, 3)
        XCTAssertEqual(openController.context.sourceFileURL, savedURL)
        XCTAssertEqual(openController.lastExportedPDFURL, savedURL)
        XCTAssertNotNil(openController.context.pdfData)
        XCTAssertEqual(openController.exportStatusMessage, "PDF saved.")
    }

    @MainActor
    func testAccountServiceTrimsDisplayNameAndFallsBackToDefault() {
        let service = AccountService()

        service.updateDisplayName("  Studio Space  ")
        XCTAssertEqual(service.displayName, "Studio Space")

        service.updateDisplayName("   ")
        XCTAssertEqual(service.displayName, "My Scanova")
    }

    private func makeImage(_ color: UIColor, size: CGSize = CGSize(width: 40, height: 60)) -> UIImage {
        UIGraphicsImageRenderer(size: size).image { context in
            color.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }

    private func removeItemIfNeeded(at url: URL?) {
        guard let url else { return }
        try? FileManager.default.removeItem(at: url)
    }

    private func deleteDocumentIfNeeded(at url: URL?, using fileStorageService: FileStorageService) {
        guard let url else { return }
        try? fileStorageService.deleteDocument(at: url)
    }
}
