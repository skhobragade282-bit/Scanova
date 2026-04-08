import PDFKit
import SwiftUI
import UniformTypeIdentifiers

struct RecentView: View {
    @EnvironmentObject private var appPreferences: AppPreferences
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var subscriptionService: SubscriptionService
    @EnvironmentObject private var workflowController: WorkflowController
    @State private var recentDocuments: [RecentDocumentItem] = []
    @State private var selectedDocumentIDs: Set<UUID> = []
    @State private var isSelectionMode = false
    @State private var libraryStatusMessage: String?
    @State private var isPerformingSelectionAction = false
    @State private var previewDocument: RecentDocumentItem?
    @State private var sortOption: DocumentsSortPreference = .newest
    @State private var documentTypeFilter: DocumentType?
    @State private var showsDeleteConfirmation = false
    @State private var sharedDocumentURLs: [URL] = []
    @State private var showsMergeSaveDialog = false
    @State private var mergedDocumentName = ""
    @State private var showsFileImporter = false
    @State private var statusMessageToken = UUID()

    private let documentLibraryService = DocumentLibraryService()
    private let photoLibraryService = PhotoLibraryService()
    private let ingestionService = DocumentIngestionService()
    private let libraryColumns = [
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                allDocumentsContent
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 140)
        }
        .background {
            ScanovaScreenBackground()
        }
        .overlay {
            if let libraryStatusMessage {
                statusToast(message: libraryStatusMessage)
                    .padding(.horizontal, 28)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }

            if showsMergeSaveDialog {
                ScanovaRenameOverlay(
                    title: "Save Merged PDF",
                    message: "Name the new PDF created from the selected files.",
                    saveTitle: "Save",
                    text: $mergedDocumentName,
                    onCancel: {
                        showsMergeSaveDialog = false
                    },
                    onSave: {
                        mergeSelectedDocuments(named: mergedDocumentName.trimmingCharacters(in: .whitespacesAndNewlines))
                        showsMergeSaveDialog = false
                    }
                )
            }
        }
        .sheet(item: $previewDocument) { item in
            ZoomableImageSheet(
                image: previewImage(for: item),
                title: item.name
            )
        }
        .sheet(isPresented: Binding(
            get: { !sharedDocumentURLs.isEmpty },
            set: { isPresented in
                if !isPresented {
                    sharedDocumentURLs = []
                }
            }
        )) {
            ActivityShareSheet(items: sharedDocumentURLs)
        }
        .fileImporter(
            isPresented: $showsFileImporter,
            allowedContentTypes: [.pdf, .image],
            allowsMultipleSelection: false
        ) { result in
            handleImportedFileSelection(result)
        }
        .alert("Delete PDFs?", isPresented: $showsDeleteConfirmation) {
            Button("Cancel", role: .cancel) {
            }

            Button("Delete", role: .destructive) {
                deleteSelectedDocuments()
            }
        } message: {
            Text("Remove the selected PDFs from Documents?")
        }
        .safeAreaInset(edge: .bottom) {
            if !showsMergeSaveDialog {
                Group {
                    if isSelectionMode {
                        ScanovaBottomBar {
                            HStack(spacing: 12) {
                                Button {
                                    sharedDocumentURLs = selectedDocuments.map(\.fileURL)
                                } label: {
                                    Image(systemName: "square.and.arrow.up")
                                        .font(ScanovaTypography.bodyEmphasis)
                                        .frame(width: 22, height: 22)
                                }
                                .buttonStyle(ScanovaGlassIconButtonStyle())
                                .disabled(isPerformingSelectionAction || selectedDocuments.isEmpty)
                                .accessibilityLabel("Share")

                                Button {
                                    showsDeleteConfirmation = true
                                } label: {
                                    Image(systemName: "trash")
                                        .font(ScanovaTypography.bodyEmphasis)
                                        .frame(width: 22, height: 22)
                                }
                                .buttonStyle(ScanovaGlassIconButtonStyle())
                                .disabled(isPerformingSelectionAction || selectedDocuments.isEmpty)
                                .accessibilityLabel("Delete")

                                Button(selectionActionTitle, action: performSelectionAction)
                                    .buttonStyle(ScanovaPrimaryButtonStyle())
                                    .disabled(isPerformingSelectionAction || selectedDocuments.isEmpty)
                            }
                        }
                    } else {
                        ScanovaPrimaryNavigationBar(
                            activeDestination: .documents,
                            onSelectHome: workflowController.showCaptureShell,
                            onSelectDocuments: {},
                            onScan: workflowController.resetDocument
                        )
                    }
                }
            }
        }
        .onAppear(perform: loadRecentDocuments)
        .scanovaBackSwipe(isEnabled: recentBackSwipeEnabled) {
            handleBackSwipe()
        }
    }

    private var header: some View {
        Group {
            if isSelectionMode {
                ScanovaTitleBar(title: "Docs") {
                    Button("Cancel", action: cancelSelectionMode)
                        .buttonStyle(ScanovaGlassButtonStyle())
                }
            } else {
                ScanovaTitleBar(title: "Docs") {
                    HStack(spacing: 10) {
                        Button("Select", action: beginSelectionMode)
                            .buttonStyle(ScanovaGlassButtonStyle())
                            .disabled(displayedDocuments.isEmpty)

                        Button {
                            showsFileImporter = true
                        } label: {
                            Image(systemName: "folder")
                                .font(.system(size: 17, weight: .semibold))
                                .frame(width: 22, height: 22)
                        }
                        .buttonStyle(ScanovaGlassIconButtonStyle())
                        .accessibilityLabel("Open from Files")

                        Menu {
                            Section("Sort") {
                                ForEach(DocumentsSortPreference.allCases, id: \.self) { option in
                                    Button {
                                        sortOption = option
                                        appPreferences.updateDefaultDocumentsSort(option)
                                    } label: {
                                        if sortOption == option {
                                            Label(option.title, systemImage: "checkmark")
                                        } else {
                                            Text(option.title)
                                        }
                                    }
                                }
                            }

                            Section("Type") {
                                Button {
                                    documentTypeFilter = nil
                                } label: {
                                    if documentTypeFilter == nil {
                                        Label("All Types", systemImage: "checkmark")
                                    } else {
                                        Text("All Types")
                                    }
                                }

                                ForEach(DocumentType.allCases, id: \.self) { type in
                                    Button {
                                        documentTypeFilter = type
                                    } label: {
                                        if documentTypeFilter == type {
                                            Label(appPreferences.displayName(for: type), systemImage: "checkmark")
                                        } else {
                                            Text(appPreferences.displayName(for: type))
                                        }
                                    }
                                }
                            }
                        } label: {
                            Image(systemName: "line.3.horizontal.decrease.circle")
                                .font(.system(size: 17, weight: .semibold))
                                .frame(width: 22, height: 22)
                        }
                        .buttonStyle(ScanovaGlassIconButtonStyle())
                    }
                }
            }
        }
    }

    private var allDocumentsContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            if isSelectionMode {
                HStack {
                    ScanovaSectionTitle("Choose PDFs")
                    Spacer()
                    Text("\(selectedDocuments.count) selected")
                        .font(ScanovaTypography.supporting)
                        .foregroundStyle(ScanovaPalette.inkMuted)
                }
            }

            if recentDocuments.isEmpty {
                Text("No PDFs yet.")
                    .foregroundStyle(ScanovaPalette.inkMuted)
                    .padding(.top, 8)
            } else {
                if isSelectionMode {
                    LazyVGrid(columns: libraryColumns, spacing: 12) {
                        ForEach(displayedDocuments) { item in
                            documentSelectionTile(for: item)
                        }
                    }
                } else {
                    LazyVGrid(columns: libraryColumns, spacing: 14) {
                        ForEach(displayedDocuments) { item in
                            documentLibraryTile(for: item)
                        }
                    }
                }
            }
        }
    }

    private func loadRecentDocuments() {
        sortOption = appPreferences.defaultDocumentsSort
        recentDocuments = documentLibraryService.fetchRecentDocuments()
    }

    private func beginSelectionMode() {
        isSelectionMode = true
        selectedDocumentIDs.removeAll()
        libraryStatusMessage = nil
    }

    private func cancelSelectionMode() {
        isSelectionMode = false
        selectedDocumentIDs.removeAll()
        isPerformingSelectionAction = false
    }

    private var displayedDocuments: [RecentDocumentItem] {
        let filtered = recentDocuments.filter { item in
            documentTypeFilter.map { item.documentType == $0 } ?? true
        }

        switch sortOption {
        case .newest:
            return filtered.sorted { $0.modifiedAt > $1.modifiedAt }
        case .oldest:
            return filtered.sorted { $0.modifiedAt < $1.modifiedAt }
        case .name:
            return filtered.sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
        }
    }

    private var selectedDocuments: [RecentDocumentItem] {
        displayedDocuments.filter { selectedDocumentIDs.contains($0.id) }
    }

    private var selectionActionTitle: String {
        if selectedDocuments.isEmpty {
            return "Select PDFs"
        }

        if isPerformingSelectionAction {
            return selectedDocuments.count > 1 ? "Merging..." : "Converting..."
        }

        if selectedDocuments.count > 1 {
            return "Merge PDFs"
        }

        return "Convert to Images"
    }

    private func performSelectionAction() {
        guard !selectedDocuments.isEmpty else { return }

        if selectedDocuments.count == 1, let document = selectedDocuments.first {
            guard subscriptionService.requirePremium(.convertToImages, router: router) else { return }
            Task {
                await convertDocumentToImages(document)
            }
        } else {
            guard subscriptionService.requirePremium(.merge, router: router) else { return }
            mergedDocumentName = defaultMergedName
            showsMergeSaveDialog = true
        }
    }

    private func mergeSelectedDocuments(named proposedName: String) {
        guard selectedDocuments.count >= 2 else { return }

        isPerformingSelectionAction = true

        do {
            let mergedName = proposedName.isEmpty ? defaultMergedName : proposedName
            let mergedItem = try documentLibraryService.mergeDocuments(selectedDocuments, outputName: mergedName)
            cancelSelectionMode()
            loadRecentDocuments()
            workflowController.openRecentDocument(mergedItem)
        } catch {
            showLibraryStatus(error.localizedDescription, autoDismiss: false)
            isPerformingSelectionAction = false
        }
    }

    private var defaultMergedName: String {
        let documents = selectedDocuments
        let firstName = documents.first?.name ?? "Merged PDF"
        if documents.count == 2 {
            return "\(firstName) + 1 More"
        }

        return "\(firstName) + \(max(documents.count - 1, 1)) More"
    }

    @MainActor
    private func convertDocumentToImages(_ item: RecentDocumentItem) async {
        isPerformingSelectionAction = true

        do {
            let renderedImages = try documentLibraryService.renderedImages(for: item)
            _ = try documentLibraryService.exportDocumentAsImages(item)
            try await photoLibraryService.save(images: renderedImages)
            cancelSelectionMode()
            showLibraryStatus("Saved \(renderedImages.count) image\(renderedImages.count == 1 ? "" : "s") to Photos.")
        } catch {
            showLibraryStatus(error.localizedDescription, autoDismiss: false)
            isPerformingSelectionAction = false
        }
    }

    private func deleteSelectedDocuments() {
        guard !selectedDocuments.isEmpty else { return }
        isPerformingSelectionAction = true

        do {
            let deletedCount = selectedDocuments.count
            try documentLibraryService.deleteDocuments(selectedDocuments)
            cancelSelectionMode()
            loadRecentDocuments()
            showLibraryStatus("Deleted \(deletedCount) PDF\(deletedCount == 1 ? "" : "s").")
        } catch {
            showLibraryStatus(error.localizedDescription, autoDismiss: false)
            isPerformingSelectionAction = false
        }
    }

    private func openDocument(_ item: RecentDocumentItem) {
        if requiresPassword(item) {
            workflowController.showProtectedRecentDocument(item)
        } else {
            workflowController.openRecentDocument(item)
        }
    }

    private func handleImportedFileSelection(_ result: Result<[URL], Error>) {
        switch result {
        case let .success(urls):
            guard let url = urls.first else { return }
            do {
                let importedDocument = try ingestionService.importFile(from: url)
                workflowController.ingest(importedDocument)
            } catch let error as DocumentImportError {
                showLibraryStatus(error.errorDescription ?? "Could not open that file.", autoDismiss: false)
            } catch {
                showLibraryStatus("Could not open that file.", autoDismiss: false)
            }
        case .failure:
            break
        }
    }

    private func requiresPassword(_ item: RecentDocumentItem) -> Bool {
        guard let document = PDFDocument(url: item.fileURL) else { return false }
        return document.isLocked
    }

    @ViewBuilder
    private func documentLibraryTile(for item: RecentDocumentItem) -> some View {
        Button {
            if isSelectionMode {
                toggleSelection(for: item)
            } else {
                libraryStatusMessage = nil
                openDocument(item)
            }
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                ZStack(alignment: .topTrailing) {
                    documentThumbnail(for: item, width: 146, height: 188)
                        .frame(maxWidth: .infinity)

                    HStack(spacing: 6) {
                        Image(systemName: "doc.text")
                            .font(.caption2.weight(.bold))
                        Text("\(item.pageCount)")
                            .font(ScanovaTypography.caption)
                    }
                    .foregroundStyle(ScanovaPalette.inkSoft)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color.white.opacity(0.92), in: Capsule())
                    .overlay {
                        Capsule()
                            .stroke(ScanovaPalette.line, lineWidth: 1)
                    }
                    .padding(12)
                }
                .overlay(alignment: .topLeading) {
                    Text(appPreferences.displayName(for: item.documentType))
                        .font(ScanovaTypography.caption)
                        .foregroundStyle(ScanovaPalette.accentDark)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(ScanovaPalette.accentSoft, in: Capsule())
                        .padding(12)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(item.name)
                        .font(ScanovaTypography.supporting)
                        .foregroundStyle(ScanovaPalette.ink)
                        .lineLimit(2)
                        .frame(minHeight: 40, alignment: .topLeading)
                        .multilineTextAlignment(.leading)

                    HStack(spacing: 4) {
                        Text(item.modifiedAt.formatted(date: .abbreviated, time: .omitted))
                            .font(ScanovaTypography.caption)
                            .foregroundStyle(ScanovaPalette.inkMuted)

                        Text("•")
                            .font(ScanovaTypography.caption)
                            .foregroundStyle(ScanovaPalette.inkMuted.opacity(0.55))

                        Text(formattedFileSize(for: item.fileSizeBytes))
                            .font(ScanovaTypography.caption)
                            .foregroundStyle(ScanovaPalette.inkMuted)
                            .lineLimit(1)
                    }
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, minHeight: 256, alignment: .topLeading)
            .background(Color.white.opacity(0.82), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color.white.opacity(0.7), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    private func toggleSelection(for item: RecentDocumentItem) {
        if selectedDocumentIDs.contains(item.id) {
            selectedDocumentIDs.remove(item.id)
        } else {
            selectedDocumentIDs.insert(item.id)
        }
    }

    private func formattedFileSize(for bytes: Int) -> String {
        guard bytes > 0 else { return "—" }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        formatter.countStyle = .file
        formatter.includesUnit = true
        return formatter.string(fromByteCount: Int64(bytes))
    }

    private func statusToast(message: String) -> some View {
        VStack(spacing: 14) {
            Text(message)
                .font(ScanovaTypography.bodyEmphasis)
                .foregroundStyle(ScanovaPalette.ink)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.white.opacity(0.5), lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.08), radius: 22, x: 0, y: 12)
    }

    private func showLibraryStatus(_ message: String, autoDismiss: Bool = true) {
        let token = UUID()
        statusMessageToken = token
        withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
            libraryStatusMessage = message
        }

        guard autoDismiss else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            guard statusMessageToken == token else { return }
            withAnimation(.easeOut(duration: 0.2)) {
                libraryStatusMessage = nil
            }
        }
    }

    private func documentThumbnail(for item: RecentDocumentItem, width: CGFloat, height: CGFloat) -> some View {
        let image = PDFDocument(url: item.fileURL)?
            .page(at: 0)?
            .thumbnail(of: CGSize(width: width * 2, height: height * 2), for: .mediaBox)

        return ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.95))

            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding(6)
            } else {
                Image(systemName: "doc.richtext")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(ScanovaPalette.accentDark)
            }
        }
        .frame(width: width, height: height)
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(ScanovaPalette.line, lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 4)
    }

    private func documentSelectionTile(for item: RecentDocumentItem) -> some View {
        let isSelected = selectedDocumentIDs.contains(item.id)

        return ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 10) {
                documentThumbnail(for: item, width: 132, height: 168)

                Text(item.name)
                    .font(ScanovaTypography.supporting)
                    .foregroundStyle(ScanovaPalette.ink)
                    .lineLimit(2)
            }
            .padding(10)
            .background(
                isSelected ? ScanovaPalette.accentSoft.opacity(0.96) : Color.white.opacity(0.88),
                in: RoundedRectangle(cornerRadius: 22, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(isSelected ? ScanovaPalette.accent : ScanovaPalette.line, lineWidth: isSelected ? 2 : 1)
            }

            ZStack {
                Circle()
                    .fill(isSelected ? ScanovaPalette.accent : Color.white.opacity(0.96))
                    .frame(width: 28, height: 28)
                Image(systemName: isSelected ? "checkmark" : "circle")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(isSelected ? Color.white : ScanovaPalette.inkSoft)
            }
            .padding(16)
        }
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .onTapGesture {
            toggleSelection(for: item)
        }
        .onLongPressGesture(minimumDuration: 0.3) {
            previewDocument = item
        }
    }

    private func previewImage(for item: RecentDocumentItem, width: CGFloat = 360, height: CGFloat = 520) -> UIImage {
        PDFDocument(url: item.fileURL)?
            .page(at: 0)?
            .thumbnail(of: CGSize(width: width, height: height), for: .mediaBox)
        ?? UIImage()
    }

    private var recentBackSwipeEnabled: Bool {
        !showsMergeSaveDialog &&
        !showsDeleteConfirmation &&
        previewDocument == nil &&
        sharedDocumentURLs.isEmpty
    }

    private func handleBackSwipe() {
        if isSelectionMode {
            cancelSelectionMode()
        } else {
            workflowController.showCaptureShell()
        }
    }
}
