import PhotosUI
import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct ExportView: View {
    @EnvironmentObject private var appPreferences: AppPreferences
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var subscriptionService: SubscriptionService
    @EnvironmentObject private var workflowController: WorkflowController
    @State private var showsRenameDialog = false
    @State private var showsDeleteConfirmation = false
    @State private var draftDocumentName = ""
    @State private var selectedPageID: UUID?
    @State private var cropPageID: UUID?
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var showsAddOptions = false
    @State private var showsPhotoPicker = false
    @State private var isLoadingImportedPages = false
    @State private var isShowingDocumentCamera = false
    @State private var errorMessage: String?
    @State private var transientMessage: String?
    @State private var showsSignatureSourceDialog = false
    @State private var showsSignatureDrawingSheet = false
    @State private var showsSignaturePhotoPicker = false
    @State private var showsSignatureFileImporter = false
    @State private var showsStampPicker = false
    @State private var showsShapePicker = false
    @State private var activeInsertDraft: PreviewInsertDraft?
    @State private var previewPDFCache: [UUID: Data] = [:]
    @State private var previewPageSignatures: [UUID: String] = [:]
    @State private var previewCacheTask: Task<Void, Never>?
    @State private var transientMessageTask: Task<Void, Never>?

    private let ingestionService = DocumentIngestionService()
    private let pdfService = PDFService()
    private let previewChromeMaxWidth: CGFloat = 340

    var body: some View {
        ZStack {
            ScanovaScreenBackground()

            previewStage

            VStack {
                previewHeader
                    .frame(maxWidth: previewChromeMaxWidth)
                    .padding(.horizontal, 26)
                    .padding(.top, 10)

                Spacer()
            }

            VStack {
                Spacer()
                if !showsRenameDialog && !workflowController.isShowingExportOptions {
                    bottomEditingStack
                }
            }

            if let errorMessage {
                VStack {
                    Spacer()
                    ScanovaCard(accent: .red) {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(.headline)
                            .foregroundStyle(.red)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 220)
                }
                .transition(.opacity)
            }

            if let transientMessage {
                VStack {
                    Spacer()
                    ScanovaCard(accent: ScanovaPalette.accent) {
                        Label(transientMessage, systemImage: "sparkles")
                            .font(ScanovaTypography.supporting)
                            .foregroundStyle(ScanovaPalette.ink)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 220)
                }
                .transition(.opacity)
            }

            if showsAddOptions {
                addPagesOverlay
            }

            if showsRenameDialog {
                renameOverlay
            }

            if workflowController.isShowingExportOptions {
                exportOptionsPage
            }

            if isLoadingImportedPages {
                ZStack {
                    Color.black.opacity(0.08).ignoresSafeArea()
                    ProgressView("Adding Pages…")
                        .padding()
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
            }

            if workflowController.isApplyingPreviewEdit {
                ZStack {
                    Color.black.opacity(0.08).ignoresSafeArea()
                    ProgressView("Updating Page…")
                        .padding()
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
            }
        }
        .task(id: selectedPhotoItems) {
            await handlePhotoImport()
        }
        .photosPicker(
            isPresented: $showsPhotoPicker,
            selection: $selectedPhotoItems,
            maxSelectionCount: 20,
            matching: .images
        )
        .fileImporter(
            isPresented: $showsSignatureFileImporter,
            allowedContentTypes: [.image],
            allowsMultipleSelection: false
        ) { result in
            handleSignatureFileSelection(result)
        }
        .onAppear {
            draftDocumentName = workflowController.context.name
            syncSelectionWithPages()
            refreshPreviewCache()
        }
        .onChange(of: previewCacheSignature) { _, _ in
            syncSelectionWithPages()
            refreshPreviewCache()
        }
        .onChange(of: selectedPageID) { _, _ in
            warmSelectedPreviewPDF()
        }
        .onChange(of: workflowController.lastRestoredPageID) { _, restoredPageID in
            guard let restoredPageID else { return }
            selectedPageID = restoredPageID
            warmSelectedPreviewPDF()
        }
        .onDisappear {
            previewCacheTask?.cancel()
            transientMessageTask?.cancel()
        }
        .sheet(isPresented: Binding(
            get: { cropPageID != nil },
            set: { isPresented in
                if !isPresented {
                    cropPageID = nil
                }
            }
        )) {
            if let index = selectedPageIndex(for: cropPageID),
               workflowController.context.pages.indices.contains(index) {
                CropImageSheet(
                    image: workflowController.context.pages[index].image,
                    title: "Crop Page \(index + 1)"
                ) { croppedImage in
                    workflowController.replacePageImage(at: index, with: croppedImage)
                }
            }
        }
        .sheet(isPresented: $isShowingDocumentCamera) {
            DocumentCameraSheet(
                onScan: handleDocumentScan,
                onCancel: { isShowingDocumentCamera = false },
                onError: handleDocumentCameraError
            )
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showsSignatureDrawingSheet) {
            SignatureDrawingSheet(
                onCancel: { showsSignatureDrawingSheet = false },
                onSave: { image in
                    RecentSignatureStore.save(image)
                    showsSignatureDrawingSheet = false
                    prepareInsertDraft(
                        PreviewInsertDraft(
                            tool: .insertSignature,
                            title: "Place Signature",
                            overlayImage: image
                        )
                    )
                }
            )
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showsSignaturePhotoPicker) {
            SignaturePhotoPickerSheet(
                onSelect: { image in
                    showsSignaturePhotoPicker = false
                    RecentSignatureStore.save(image)

                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(180))
                        prepareInsertDraft(
                            PreviewInsertDraft(
                                tool: .insertSignature,
                                title: "Place Signature",
                                overlayImage: image
                            )
                        )
                    }
                },
                onCancel: {
                    showsSignaturePhotoPicker = false
                },
                onError: {
                    showsSignaturePhotoPicker = false
                    showTransientMessage("Couldn’t load that signature image.")
                }
            )
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showsStampPicker) {
            StampPickerSheet(
                onCancel: { showsStampPicker = false },
                onApply: { configuration in
                    showsStampPicker = false
                    prepareInsertDraft(
                        PreviewInsertDraft(
                            tool: .insertStamp,
                            title: "Place Stamp",
                            overlayImage: configuration.makeOverlayImage()
                        )
                    )
                }
            )
        }
        .sheet(isPresented: $showsShapePicker) {
            ShapePickerSheet(
                onCancel: { showsShapePicker = false },
                onApply: { configuration in
                    showsShapePicker = false
                    prepareInsertDraft(
                        PreviewInsertDraft(
                            tool: .insertShapes,
                            title: "Place Shape",
                            overlayImage: configuration.makeOverlayImage()
                        )
                    )
                }
            )
        }
        .fullScreenCover(item: $activeInsertDraft) { draft in
            if let index = selectedPageIndex(for: selectedPageID),
               workflowController.context.pages.indices.contains(index) {
                InsertPlacementSheet(
                    title: draft.title,
                    pageImage: workflowController.context.pages[index].image,
                    overlayImage: draft.overlayImage,
                    onCancel: { activeInsertDraft = nil },
                    onApply: { placement in
                        workflowController.insertOverlayImage(draft.overlayImage, at: index, placement: placement)
                        activeInsertDraft = nil
                    }
                )
            }
        }
        .alert("Delete Page?", isPresented: $showsDeleteConfirmation) {
            Button("Cancel", role: .cancel) {
            }

            Button("Delete", role: .destructive) {
                guard let selectedPageID else { return }
                deletePage(selectedPageID)
            }
        } message: {
            Text("Remove the selected page from this document?")
        }
        .confirmationDialog("Insert Signature", isPresented: $showsSignatureSourceDialog, titleVisibility: .visible) {
            if let signature = RecentSignatureStore.load() {
                Button("Use Recent Signature") {
                    prepareInsertDraft(
                        PreviewInsertDraft(
                            tool: .insertSignature,
                            title: "Place Signature",
                            overlayImage: signature
                        )
                    )
                }
            }

            Button("Draw Signature") {
                showsSignatureDrawingSheet = true
            }

            Button("Choose from Photos") {
                showsSignaturePhotoPicker = true
            }

            Button("Choose from Files") {
                showsSignatureFileImporter = true
            }

            Button("Cancel", role: .cancel) {
            }
        } message: {
            Text("Choose how you’d like to add your signature.")
        }
        .scanovaBackSwipe(isEnabled: previewBackSwipeEnabled) {
            handleBackSwipe()
        }
    }

    private var previewStage: some View {
        GeometryReader { geometry in
            ZStack {
                if let selectedPreviewPage {
                    PreviewCanvasBackdrop(page: selectedPreviewPage, size: geometry.size)
                        .transaction { transaction in
                            transaction.animation = nil
                        }

                    PreviewCarousel(
                        pages: workflowController.context.pages,
                        selectedPageID: $selectedPageID,
                        previewPDFCache: previewPDFCache
                    )
                    .padding(.top, 140)
                    .padding(.bottom, 126)
                } else {
                    RoundedRectangle(cornerRadius: 0, style: .continuous)
                        .fill(Color.white.opacity(0.92))
                        .overlay {
                            ProgressView()
                        }
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .ignoresSafeArea()
    }

    private var addPagesOverlay: some View {
        AddPagesOverlay(
            onDismiss: { showsAddOptions = false },
            onPhotos: {
                showsAddOptions = false
                showsPhotoPicker = true
            },
            onScan: {
                showsAddOptions = false
                isShowingDocumentCamera = true
            }
        )
        .transition(.opacity.combined(with: .scale(scale: 0.98)))
    }

    private var renameOverlay: some View {
        ScanovaRenameOverlay(
            title: "Rename PDF",
            message: "Update the document name before saving.",
            text: $draftDocumentName,
            onCancel: {
                draftDocumentName = workflowController.context.name
                showsRenameDialog = false
            },
            onSave: {
                saveDocumentName()
                showsRenameDialog = false
            }
        )
        .transition(.opacity.combined(with: .scale(scale: 0.98)))
    }

    private var previewHeader: some View {
        PreviewHeaderCard(
            title: workflowController.context.name,
            detectedType: workflowController.context.detectedType,
            onBack: workflowController.goToPreviousStep,
            onRename: {
                draftDocumentName = workflowController.context.name
                showsRenameDialog = true
            },
            onTypeSelected: workflowController.updateDetectedType
        )
    }

    private var bottomEditingStack: some View {
        refineToolbar
            .frame(maxWidth: previewChromeMaxWidth)
            .padding(.horizontal, 26)
            .padding(.bottom, 8)
    }

    private var exportOptionsPage: some View {
        PreviewExportOptionsPage(
            options: $workflowController.exportOptions,
            isSubscribed: subscriptionService.isSubscribed,
            validationMessage: exportOptionsValidationMessage,
            currentFileSizeBytes: currentPDFSizeBytes,
            outputFileSizeBytes: estimatedOutputFileSizeBytes,
            onDismiss: workflowController.dismissExportOptions,
            onCompressionTapped: {
                if !subscriptionService.isSubscribed {
                    subscriptionService.requestPaywall(for: .compress)
                    router.showPaywall()
                } else {
                    workflowController.exportOptions.isCompressionEnabled.toggle()
                }
            },
            onProtectionTapped: {
                if !subscriptionService.isSubscribed {
                    subscriptionService.requestPaywall(for: .passwordProtection)
                    router.showPaywall()
                } else {
                    workflowController.exportOptions.isPasswordProtectionEnabled.toggle()
                }
            },
            onSave: saveConfiguredPDF
        )
        .transition(.move(edge: .trailing).combined(with: .opacity))
    }

    private var currentPDFSizeBytes: Int {
        if let pdfData = workflowController.context.pdfData, !pdfData.isEmpty {
            return pdfData.count
        }

        return pdfService.createPDFData(from: workflowController.context.images)?.count ?? 0
    }

    private var estimatedOutputFileSizeBytes: Int {
        let currentBytes = currentPDFSizeBytes
        guard currentBytes > 0 else { return 0 }
        guard workflowController.exportOptions.isCompressionEnabled else { return currentBytes }

        let compressionRatio = workflowController.exportOptions.compressionPercent / 100
        let minimumRetention = 0.22
        let retainedSizeFactor = 1.0 - (compressionRatio * (1.0 - minimumRetention))
        return max(Int((Double(currentBytes) * retainedSizeFactor).rounded()), 1)
    }

    private var refineToolbar: some View {
        ScanovaBottomBar {
            HStack(spacing: 10) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        toolbarButton(
                            systemImage: "arrow.counterclockwise",
                            accessibilityLabel: "Reset Edits",
                            isEnabled: workflowController.canResetPreviewOperations
                        ) {
                            workflowController.resetPreviewOperations()
                        }

                        toolbarButton(
                            systemImage: "crop",
                            accessibilityLabel: "Crop",
                            isEnabled: selectedPageID != nil
                        ) {
                            cropPageID = selectedPageID
                        }

                        toolbarButton(
                            systemImage: "rotate.right",
                            accessibilityLabel: "Rotate",
                            isEnabled: selectedPageID != nil
                        ) {
                            rotateSelectedPage()
                        }

                        toolbarButton(
                            systemImage: "plus",
                            accessibilityLabel: "Add Page",
                            isEnabled: true
                        ) {
                            showsAddOptions = true
                        }

                        toolbarButton(
                            systemImage: "trash",
                            accessibilityLabel: "Delete Page",
                            isEnabled: selectedPageID != nil
                        ) {
                            showsDeleteConfirmation = true
                        }

                        toolbarButton(
                            systemImage: "signature",
                            accessibilityLabel: "Insert Signature",
                            isEnabled: selectedPageID != nil
                        ) {
                            handleExportToolSelection(.insertSignature)
                        }

                        toolbarButton(
                            systemImage: "seal",
                            accessibilityLabel: "Insert Stamp",
                            isEnabled: selectedPageID != nil
                        ) {
                            handleExportToolSelection(.insertStamp)
                        }

                        toolbarButton(
                            systemImage: "square.on.circle",
                            accessibilityLabel: "Insert Shapes",
                            isEnabled: selectedPageID != nil
                        ) {
                            handleExportToolSelection(.insertShapes)
                        }
                    }
                    .padding(.trailing, 10)
                }
                .scrollClipDisabled()
                .frame(maxWidth: .infinity, alignment: .leading)

                Button(action: primaryFooterAction) {
                    Text(primaryToolbarTitle)
                        .font(ScanovaTypography.button)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 13)
                        .frame(minWidth: 92)
                        .background(
                            Capsule(style: .continuous)
                                .fill(ScanovaPalette.accent)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(primaryToolbarAccessibilityLabel)
                .accessibilityHint(primaryToolbarAccessibilityLabel)
                .accessibilityAddTraits(.isButton)
                .padding(.leading, 2)
            }
        }
    }

    private var primaryToolbarTitle: String {
        return "Save"
    }

    private var primaryToolbarAccessibilityLabel: String {
        return "Save PDF"
    }

    private func toolbarButton(
        systemImage: String,
        accessibilityLabel: String,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            PreviewFooterToolChip(systemImage: systemImage, isEnabled: isEnabled)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel(accessibilityLabel)
    }

    private func toolbarForeground(isPrimary: Bool, isEnabled: Bool) -> Color {
        if !isEnabled {
            return ScanovaPalette.inkMuted.opacity(0.55)
        }

        return isPrimary ? .white : ScanovaPalette.ink
    }

    private func toolbarBackground(isPrimary: Bool, isEnabled: Bool) -> Color {
        if !isEnabled {
            return ScanovaPalette.cloud.opacity(0.55)
        }

        return isPrimary ? ScanovaPalette.accent : Color.white.opacity(0.92)
    }

    private var selectedPreviewPage: DocumentPage? {
        if let selectedPageID,
           let page = workflowController.context.pages.first(where: { $0.id == selectedPageID }) {
            return page
        }

        return workflowController.context.pages.first
    }

    private var previewCacheSignature: [String] {
        workflowController.context.pages.map { page in
            let width = Int(page.image.size.width.rounded())
            let height = Int(page.image.size.height.rounded())
            return "\(page.id.uuidString)-\(width)x\(height)-\(page.image.hashValue)"
        }
    }

    private func selectedPageIndex(for pageID: UUID?) -> Int? {
        guard let pageID else { return nil }
        return workflowController.context.pages.firstIndex(where: { $0.id == pageID })
    }

    private func refreshPreviewCache() {
        let currentPages = workflowController.context.pages
        let currentIDs = Set(currentPages.map(\.id))
        previewPDFCache = previewPDFCache.filter { currentIDs.contains($0.key) }
        previewPageSignatures = previewPageSignatures.filter { currentIDs.contains($0.key) }

        for page in currentPages {
            let signature = previewSignature(for: page)
            if previewPageSignatures[page.id] != signature {
                previewPDFCache[page.id] = nil
                previewPageSignatures[page.id] = signature
            }
        }

        warmSelectedPreviewPDF()
    }

    private func warmSelectedPreviewPDF() {
        previewCacheTask?.cancel()

        let warmEntries = pagesToWarmForSelection().map { page in
            (id: page.id, image: page.image, signature: previewSignature(for: page))
        }
        guard !warmEntries.isEmpty else { return }

        let service = pdfService

        previewCacheTask = Task.detached(priority: .userInitiated) {
            for entry in warmEntries {
                guard !Task.isCancelled else { return }
                let pdfData = service.createPDFData(from: [entry.image])

                await MainActor.run {
                    guard previewPageSignatures[entry.id] == entry.signature else { return }
                    previewPDFCache[entry.id] = pdfData
                }
            }
        }
    }

    private func pagesToWarmForSelection() -> [DocumentPage] {
        let pages = workflowController.context.pages
        guard !pages.isEmpty else { return [] }

        let currentIndex = selectedPageIndex(for: selectedPageID) ?? 0
        let candidateIndexes = [currentIndex, currentIndex + 1, currentIndex - 1]

        return candidateIndexes.compactMap { index in
            guard pages.indices.contains(index) else { return nil }
            let page = pages[index]
            return previewPDFCache[page.id] == nil ? page : nil
        }
    }

    private func previewSignature(for page: DocumentPage) -> String {
        let width = Int(page.image.size.width.rounded())
        let height = Int(page.image.size.height.rounded())
        let scale = Int(page.image.scale.rounded())
        return "\(width)x\(height)-\(scale)-\(page.image.imageOrientation.rawValue)-\(page.image.hashValue)"
    }

    private func syncSelectionWithPages() {
        let pageIDs = Set(workflowController.context.pages.map(\.id))

        if let selectedPageID, pageIDs.contains(selectedPageID) {
            return
        }

        selectedPageID = workflowController.context.pages.first?.id
    }

    private func rotateSelectedPage() {
        guard let selectedIndex = selectedPageIndex(for: selectedPageID) else { return }
        workflowController.rotatePage(at: selectedIndex, clockwise: true)
    }

    private var previewBackSwipeEnabled: Bool {
        !showsRenameDialog &&
        !showsDeleteConfirmation &&
        cropPageID == nil &&
        !isShowingDocumentCamera &&
        !showsPhotoPicker &&
        !isLoadingImportedPages &&
        !workflowController.isApplyingPreviewEdit
    }

    private func handleBackSwipe() {
        if showsAddOptions {
            showsAddOptions = false
        } else if workflowController.isShowingExportOptions {
            workflowController.dismissExportOptions()
        } else {
            workflowController.goToPreviousStep()
        }
    }

    private func deletePage(_ pageID: UUID) {
        guard let index = selectedPageIndex(for: pageID) else { return }
        let previousIndex = max(0, index - 1)
        workflowController.removeImage(at: index)

        if workflowController.context.pages.isEmpty {
            workflowController.resetDocument()
            return
        }

        if workflowController.context.pages.indices.contains(previousIndex) {
            selectedPageID = workflowController.context.pages[previousIndex].id
        } else {
            selectedPageID = workflowController.context.pages.first?.id
        }
    }

    private func primaryFooterAction() {
        if workflowController.lastExportedPDFURL != nil {
            workflowController.showRecentDocuments()
        } else {
            workflowController.presentExportOptions()
        }
    }

    private func saveDocumentName() {
        let trimmed = draftDocumentName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            draftDocumentName = workflowController.context.name
            return
        }

        workflowController.updateName(trimmed)
        draftDocumentName = workflowController.context.name
    }

    private var exportOptionsValidationMessage: String? {
        let options = workflowController.exportOptions
        if options.isPasswordProtectionEnabled {
            let trimmedPassword = options.password.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedConfirmation = options.passwordConfirmation.trimmingCharacters(in: .whitespacesAndNewlines)

            if trimmedPassword.isEmpty || trimmedConfirmation.isEmpty {
                return "Enter and confirm a password to continue."
            }

            if trimmedPassword != trimmedConfirmation {
                return "Passwords do not match."
            }
        }

        return nil
    }

    private func saveConfiguredPDF() {
        guard exportOptionsValidationMessage == nil else { return }
        workflowController.savePDF(using: workflowController.exportOptions)
    }

    private func handleExportToolSelection(_ feature: SubscriptionService.PremiumFeature) {
        if feature != .convertToImages,
           selectedPageIndex(for: selectedPageID) == nil {
            showTransientMessage("Select a page before adding something to it.")
            return
        }

        guard subscriptionService.requirePremium(feature, router: router) else { return }

        switch feature {
        case .convertToImages:
            workflowController.exportCurrentPagesAsImages()
            showTransientMessage(workflowController.exportStatusMessage)
        case .insertSignature:
            showsSignatureSourceDialog = true
        case .insertStamp:
            showsStampPicker = true
        case .insertShapes:
            showsShapePicker = true
        case .compress, .passwordProtection, .merge, .split, .deletePages, .reorderPages:
            break
        }
    }

    private func showTransientMessage(_ message: String) {
        transientMessageTask?.cancel()
        transientMessage = message

        transientMessageTask = Task {
            try? await Task.sleep(for: .seconds(2.4))
            guard !Task.isCancelled else { return }

            await MainActor.run {
                withAnimation(.easeOut(duration: 0.18)) {
                    transientMessage = nil
                }
            }
        }
    }

    @MainActor
    private func handlePhotoImport() async {
        guard !selectedPhotoItems.isEmpty else { return }

        isLoadingImportedPages = true
        defer {
            isLoadingImportedPages = false
            selectedPhotoItems = []
        }

        do {
            let imported = try await ingestionService.importPhotos(from: selectedPhotoItems)
            errorMessage = nil
            workflowController.insertPages(imported.pages, afterPageID: nil)
            selectedPageID = imported.pages.first?.id ?? workflowController.context.pages.last?.id
        } catch {
            let importError = error as? LocalizedError
            errorMessage = importError?.errorDescription ?? error.localizedDescription
        }
    }

    private func handleSignatureFileSelection(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result,
              let fileURL = urls.first else {
            if case .failure = result {
                showTransientMessage("Couldn’t open that file.")
            }
            return
        }

        do {
            let accessGranted = fileURL.startAccessingSecurityScopedResource()
            defer {
                if accessGranted {
                    fileURL.stopAccessingSecurityScopedResource()
                }
            }

            let data = try Data(contentsOf: fileURL)
            guard let image = UIImage(data: data) else {
                showTransientMessage("Choose an image file for your signature.")
                return
            }

            RecentSignatureStore.save(image)
            prepareInsertDraft(
                PreviewInsertDraft(
                    tool: .insertSignature,
                    title: "Place Signature",
                    overlayImage: image
                )
            )
        } catch {
            showTransientMessage("Couldn’t open that file.")
        }
    }

    private func prepareInsertDraft(_ draft: PreviewInsertDraft) {
        guard selectedPageIndex(for: selectedPageID) != nil else {
            showTransientMessage("Select a page before adding something to it.")
            return
        }

        activeInsertDraft = draft
    }

    private func handleDocumentScan(_ images: [UIImage]) {
        isShowingDocumentCamera = false

        do {
            let imported = try ingestionService.importScannedImages(images)
            errorMessage = nil
            workflowController.insertPages(imported.pages, afterPageID: nil)
            selectedPageID = imported.pages.first?.id ?? workflowController.context.pages.last?.id
        } catch {
            let importError = error as? LocalizedError
            errorMessage = importError?.errorDescription ?? error.localizedDescription
        }
    }

    private func handleDocumentCameraError(_ error: Error) {
        isShowingDocumentCamera = false

        if let localizedError = error as? LocalizedError,
           let description = localizedError.errorDescription,
           !description.isEmpty {
            errorMessage = description
        } else {
            errorMessage = "Could not open the scanner. Try again."
        }
    }

}

private struct PreviewCanvasBackdrop: View {
    let page: DocumentPage
    let size: CGSize

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.22, green: 0.22, blue: 0.24),
                    Color(red: 0.16, green: 0.16, blue: 0.18),
                    Color(red: 0.11, green: 0.11, blue: 0.13)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            Circle()
                .fill(ScanovaPalette.accent.opacity(0.10))
                .frame(width: size.width * 0.78)
                .blur(radius: 36)
                .offset(x: -size.width * 0.22, y: -size.height * 0.18)

            Circle()
                .fill(Color.white.opacity(0.06))
                .frame(width: size.width * 0.52)
                .blur(radius: 32)
                .offset(x: size.width * 0.28, y: size.height * 0.22)

            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.05),
                            Color.clear,
                            Color.black.opacity(0.10)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        }
        .frame(width: size.width, height: size.height)
        .clipped()
    }
}

private struct PreviewCarousel: View {
    let pages: [DocumentPage]
    @Binding var selectedPageID: UUID?
    let previewPDFCache: [UUID: Data]
    @GestureState private var dragOffset: CGFloat = 0

    var body: some View {
        GeometryReader { geometry in
            if let selectedIndex = currentIndex {
                PreviewCarouselCard(
                    page: pages[selectedIndex],
                    pageNumber: selectedIndex + 1,
                    totalPages: pages.count,
                    previewPDFData: previewPDFCache[pages[selectedIndex].id]
                )
                .frame(width: geometry.size.width, height: geometry.size.height)
                .offset(x: dragOffset)
                .contentShape(Rectangle())
                .gesture(pageSwipeGesture(pageWidth: geometry.size.width))
            }
        }
    }

    private var currentIndex: Int? {
        guard !pages.isEmpty else { return nil }
        guard let selectedPageID,
              let index = pages.firstIndex(where: { $0.id == selectedPageID }) else {
            return 0
        }
        return index
    }

    private func pageSwipeGesture(pageWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 18, coordinateSpace: .local)
            .updating($dragOffset) { value, state, _ in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                state = value.translation.width
            }
            .onEnded { value in
                guard abs(value.translation.width) > abs(value.translation.height),
                      let currentIndex else { return }

                let threshold = pageWidth * 0.16
                let projectedWidth = value.predictedEndTranslation.width

                if (value.translation.width <= -threshold || projectedWidth <= -(threshold * 1.2)),
                   pages.indices.contains(currentIndex + 1) {
                    withAnimation(.easeOut(duration: 0.18)) {
                        selectedPageID = pages[currentIndex + 1].id
                    }
                } else if (value.translation.width >= threshold || projectedWidth >= threshold * 1.2),
                          pages.indices.contains(currentIndex - 1) {
                    withAnimation(.easeOut(duration: 0.18)) {
                        selectedPageID = pages[currentIndex - 1].id
                    }
                }
            }
    }
}

private struct PreviewCarouselCard: View {
    let page: DocumentPage
    let pageNumber: Int
    let totalPages: Int
    let previewPDFData: Data?

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Rectangle()
                .fill(Color.white)

            Group {
                if let previewPDFData {
                    PDFKitPreview(
                        data: previewPDFData,
                        fitSinglePage: true,
                        resetZoomToken: page.id.uuidString
                    )
                } else {
                    Image(uiImage: page.image)
                        .resizable()
                        .scaledToFit()
                        .background(Color.white)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            pageNumberBadge
                .padding(.top, 18)
                .padding(.trailing, 18)
        }
    }

    private var pageNumberBadge: some View {
        Text(pageNumberText)
            .font(ScanovaTypography.caption)
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.black.opacity(0.24), in: Capsule(style: .continuous))
            .overlay {
                Capsule(style: .continuous)
                    .stroke(Color.white.opacity(0.16), lineWidth: 0.8)
            }
    }

    private var pageNumberText: String {
        "\(pageNumber)/\(totalPages)"
    }
}

private struct AddPagesOverlay: View {
    let onDismiss: () -> Void
    let onPhotos: () -> Void
    let onScan: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.10)
                .ignoresSafeArea()
                .onTapGesture(perform: onDismiss)

            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Add Pages")
                        .font(ScanovaTypography.cardTitle)
                        .foregroundStyle(ScanovaPalette.ink)

                    Text("Choose how to add more pages.")
                        .font(ScanovaTypography.supporting)
                        .foregroundStyle(ScanovaPalette.inkMuted)
                }

                HStack(spacing: 12) {
                    Button("Photos", action: onPhotos)
                        .buttonStyle(ScanovaSecondaryButtonStyle())

                    Button("Scan", action: onScan)
                        .buttonStyle(ScanovaSecondaryButtonStyle())
                }
            }
            .padding(22)
            .frame(maxWidth: 340, alignment: .leading)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .stroke(Color.white.opacity(0.45), lineWidth: 1)
            }
            .shadow(color: Color.black.opacity(0.10), radius: 24, x: 0, y: 14)
            .padding(.horizontal, 20)
        }
    }
}

private struct PreviewExportOptionsPage: View {
    @Binding var options: PDFExportOptions
    let isSubscribed: Bool
    let validationMessage: String?
    let currentFileSizeBytes: Int
    let outputFileSizeBytes: Int
    let onDismiss: () -> Void
    let onCompressionTapped: () -> Void
    let onProtectionTapped: () -> Void
    let onSave: () -> Void

    var body: some View {
        ZStack {
            ScanovaScreenBackground()
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    namingCard
                    standardCard
                    compressionCard
                    protectionCard
                    saveButton
                }
                .padding(.horizontal, 20)
                .padding(.top, 14)
                .padding(.bottom, 40)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            Button("Back", action: onDismiss)
                .buttonStyle(ScanovaGlassButtonStyle())

            VStack(alignment: .leading, spacing: 4) {
                Text("Save PDF")
                    .font(ScanovaTypography.heroTitle)
                    .foregroundStyle(ScanovaPalette.ink)

                Text("Choose how you'd like to save this document.")
                    .font(ScanovaTypography.supporting)
                    .foregroundStyle(ScanovaPalette.inkMuted)
            }

            Spacer(minLength: 0)
        }
    }

    private var namingCard: some View {
        ScanovaCard(accent: ScanovaPalette.cloud) {
            VStack(alignment: .leading, spacing: 10) {
                Text("File Name")
                    .font(ScanovaTypography.bodyEmphasis)
                    .foregroundStyle(ScanovaPalette.ink)

                TextField("PDF name", text: $options.fileName)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .font(ScanovaTypography.body)
                    .foregroundStyle(ScanovaPalette.ink)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 14)
                    .background(Color.white.opacity(0.82), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        }
    }

    private var standardCard: some View {
        ScanovaCard(accent: ScanovaPalette.success) {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Standard PDF")
                        .font(ScanovaTypography.bodyEmphasis)
                        .foregroundStyle(ScanovaPalette.ink)

                    Text("Save the current document as a regular PDF.")
                        .font(ScanovaTypography.supporting)
                        .foregroundStyle(ScanovaPalette.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                Text("Included")
                    .font(ScanovaTypography.caption)
                    .foregroundStyle(ScanovaPalette.success)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(ScanovaPalette.success.opacity(0.12), in: Capsule(style: .continuous))
            }
        }
    }

    private var compressionCard: some View {
        ScanovaCard(accent: options.isCompressionEnabled ? ScanovaPalette.accent : ScanovaPalette.cloud) {
            VStack(alignment: .leading, spacing: 14) {
                exportToggleRow(
                    title: "Compress PDF",
                    message: "Create a smaller PDF that's easier to send and store.",
                    isEnabled: options.isCompressionEnabled,
                    isLocked: !isSubscribed,
                    action: onCompressionTapped
                )

                if options.isCompressionEnabled {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(alignment: .firstTextBaseline) {
                            Text("Compression")
                                .font(ScanovaTypography.bodyEmphasis)
                                .foregroundStyle(ScanovaPalette.ink)

                            Spacer(minLength: 0)

                            Text("\(Int(options.compressionPercent.rounded()))%")
                                .font(ScanovaTypography.bodyEmphasis)
                                .foregroundStyle(ScanovaPalette.accent)
                        }

                        Slider(value: $options.compressionPercent, in: 0...100, step: 1)
                            .tint(ScanovaPalette.accent)

                        HStack {
                            Text("Sharper")
                                .font(ScanovaTypography.caption)
                                .foregroundStyle(ScanovaPalette.inkMuted)

                            Spacer(minLength: 0)

                            Text("Smaller File")
                                .font(ScanovaTypography.caption)
                                .foregroundStyle(ScanovaPalette.inkMuted)
                        }

                        Text(compressionDescription)
                            .font(ScanovaTypography.supporting)
                            .foregroundStyle(ScanovaPalette.inkMuted)
                            .fixedSize(horizontal: false, vertical: true)

                        HStack(spacing: 12) {
                            fileSizeStatCard(
                                title: "Current Size",
                                value: formatByteCount(currentFileSizeBytes),
                                accent: ScanovaPalette.cloud
                            )

                            fileSizeStatCard(
                                title: "Output Size",
                                value: formatByteCount(outputFileSizeBytes),
                                accent: ScanovaPalette.accentSoft
                            )
                        }

                        Text("Output size is an estimate based on your selected compression level.")
                            .font(ScanovaTypography.caption)
                            .foregroundStyle(ScanovaPalette.inkMuted)
                    }
                }
            }
        }
    }

    private var protectionCard: some View {
        ScanovaCard(accent: options.isPasswordProtectionEnabled ? ScanovaPalette.accent : ScanovaPalette.cloud) {
            VStack(alignment: .leading, spacing: 14) {
                exportToggleRow(
                    title: "Protect with Password",
                    message: "Add a password before sharing this PDF.",
                    isEnabled: options.isPasswordProtectionEnabled,
                    isLocked: !isSubscribed,
                    action: onProtectionTapped
                )

                if options.isPasswordProtectionEnabled {
                    VStack(alignment: .leading, spacing: 10) {
                        SecureField("Password", text: $options.password)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .font(ScanovaTypography.body)
                            .foregroundStyle(ScanovaPalette.ink)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 14)
                            .background(Color.white.opacity(0.82), in: RoundedRectangle(cornerRadius: 18, style: .continuous))

                        SecureField("Confirm Password", text: $options.passwordConfirmation)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .font(ScanovaTypography.body)
                            .foregroundStyle(ScanovaPalette.ink)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 14)
                            .background(Color.white.opacity(0.82), in: RoundedRectangle(cornerRadius: 18, style: .continuous))

                        if let validationMessage {
                            Text(validationMessage)
                                .font(ScanovaTypography.supporting)
                                .foregroundStyle(.red)
                        }
                    }
                }
            }
        }
    }

    private var saveButton: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("A new copy will be saved to Documents.")
                .font(ScanovaTypography.supporting)
                .foregroundStyle(ScanovaPalette.inkMuted)

            Button(action: onSave) {
                Text("Save to Documents")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(ScanovaPrimaryButtonStyle())
            .disabled(validationMessage != nil)
            .opacity(validationMessage == nil ? 1 : 0.55)
        }
    }

    private var compressionDescription: String {
        switch options.compressionPercent {
        case ..<26:
            return "Keep more detail and make only a light size reduction."
        case 26..<61:
            return "A balanced middle ground for everyday sharing and storage."
        case 61..<86:
            return "Shrink the PDF more aggressively for faster sending."
        default:
            return "Prioritize the smallest file size for quick sharing."
        }
    }

    private func fileSizeStatCard(title: String, value: String, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(ScanovaTypography.caption)
                .foregroundStyle(ScanovaPalette.inkMuted)

            Text(value)
                .font(ScanovaTypography.bodyEmphasis)
                .foregroundStyle(ScanovaPalette.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(accent.opacity(0.18))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.34), lineWidth: 0.8)
        }
    }

    private func formatByteCount(_ bytes: Int) -> String {
        guard bytes > 0 else { return "—" }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        formatter.countStyle = .file
        formatter.includesUnit = true
        return formatter.string(fromByteCount: Int64(bytes))
    }

    private func exportToggleRow(
        title: String,
        message: String,
        isEnabled: Bool,
        isLocked: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 8) {
                        Text(title)
                            .font(ScanovaTypography.bodyEmphasis)
                            .foregroundStyle(ScanovaPalette.ink)

                        if isLocked {
                            Text("Pro")
                                .font(ScanovaTypography.caption)
                                .foregroundStyle(ScanovaPalette.accent)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(ScanovaPalette.accent.opacity(0.10), in: Capsule(style: .continuous))
                        }
                    }

                    Text(message)
                        .font(ScanovaTypography.supporting)
                        .foregroundStyle(ScanovaPalette.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                Image(systemName: isLocked ? "lock.fill" : (isEnabled ? "checkmark.circle.fill" : "circle"))
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(isLocked ? ScanovaPalette.inkMuted : (isEnabled ? ScanovaPalette.accent : ScanovaPalette.line))
            }
        }
        .buttonStyle(.plain)
    }
}

private struct PreviewHeaderCard: View {
    @EnvironmentObject private var appPreferences: AppPreferences
    let title: String
    let detectedType: DocumentType
    let onBack: () -> Void
    let onRename: () -> Void
    let onTypeSelected: (DocumentType) -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Button("Back", action: onBack)
                .font(Font.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.96))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.14), in: Capsule(style: .continuous))
                .overlay {
                    Capsule(style: .continuous)
                        .stroke(Color.white.opacity(0.22), lineWidth: 0.9)
                }

            Button(action: onRename) {
                HStack(alignment: .center, spacing: 6) {
                    Text(title)
                        .font(ScanovaTypography.screenTitle)
                        .foregroundStyle(Color.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                        .allowsTightening(true)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Image(systemName: "pencil")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(ScanovaPalette.inkSoft)
                        .padding(4)
                        .background(Color.white.opacity(0.28), in: Circle())
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Spacer(minLength: 0)

            Menu {
                ForEach(DocumentType.allCases, id: \.self) { type in
                    Button(appPreferences.displayName(for: type)) {
                        onTypeSelected(type)
                    }
                }
            } label: {
                Text(appPreferences.displayName(for: detectedType))
                    .font(ScanovaTypography.chip)
                    .foregroundStyle(ScanovaPalette.accentDark.opacity(0.92))
                    .padding(.horizontal, 13)
                    .padding(.vertical, 7)
                    .background(
                        Capsule(style: .continuous)
                            .fill(ScanovaPalette.accentSoft.opacity(0.78))
                    )
                    .overlay {
                        Capsule(style: .continuous)
                            .stroke(Color.white.opacity(0.22), lineWidth: 0.8)
                    }
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.08), radius: 14, x: 0, y: 7)
    }
}

private struct PreviewToolbarIcon: View {
    let systemImage: String
    let isPrimary: Bool
    let isEnabled: Bool

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(foregroundColor)
            .frame(width: 46, height: 46)
            .background(backgroundColor, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .stroke(isPrimary ? Color.clear : ScanovaPalette.line, lineWidth: 1)
            }
    }

    private var foregroundColor: Color {
        if !isEnabled {
            return ScanovaPalette.inkMuted.opacity(0.55)
        }

        return isPrimary ? .white : ScanovaPalette.ink
    }

    private var backgroundColor: Color {
        if !isEnabled {
            return ScanovaPalette.cloud.opacity(0.55)
        }

        return isPrimary ? ScanovaPalette.accent : Color.white.opacity(0.92)
    }
}

private struct PreviewFooterToolChip: View {
    let systemImage: String
    let isEnabled: Bool

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(foregroundColor)
            .frame(width: 46, height: 46)
            .background(backgroundColor, in: Circle())
        .overlay {
            Circle()
                .stroke(borderColor, lineWidth: 1)
        }
    }

    private var foregroundColor: Color {
        isEnabled ? ScanovaPalette.ink : ScanovaPalette.inkMuted.opacity(0.55)
    }

    private var backgroundColor: Color {
        isEnabled ? Color.white.opacity(0.92) : ScanovaPalette.cloud.opacity(0.55)
    }

    private var borderColor: Color {
        isEnabled ? ScanovaPalette.line : ScanovaPalette.line.opacity(0.45)
    }
}
