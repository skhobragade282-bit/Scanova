import SwiftUI
import UniformTypeIdentifiers

struct ViewerView: View {
    private enum ManageMode {
        case select
        case reorder
    }

    @EnvironmentObject private var appPreferences: AppPreferences
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var subscriptionService: SubscriptionService
    @EnvironmentObject private var workflowController: WorkflowController
    @State private var showsSplitSaveDialog = false
    @State private var showsDeleteConfirmation = false
    @State private var showsDeleteSaveDialog = false
    @State private var showsReorderSaveDialog = false
    @State private var splitDocumentName = ""
    @State private var revisedDocumentName = ""
    @State private var reorderedDocumentName = ""
    @State private var showsRenameDialog = false
    @State private var draftDocumentName = ""
    @State private var isImmersiveReading = false
    @State private var manageMode: ManageMode = .select
    @State private var reorderDraftPages: [DocumentPage] = []
    @State private var draggedReorderPageID: UUID?
    @State private var reorderTargetPageID: UUID?

    private let gridColumns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]
    private let viewerChromeMaxWidth: CGFloat = 340

    var body: some View {
        ZStack {
            ScanovaScreenBackground()

            if isManagingPages {
                selectionContent
            } else {
                viewerContent
            }
        }
        .task {
            workflowController.generatePDFIfNeeded()
        }
        .onAppear {
            draftDocumentName = workflowController.context.name
            isImmersiveReading = false
            manageMode = .select
            syncReorderDraftPages()
        }
        .onChange(of: workflowController.context.pages.map(\.id)) { _, _ in
            if manageMode == .select || !isManagingPages {
                syncReorderDraftPages()
            }
        }
        .onChange(of: isManagingPages) { _, isManagingPages in
            guard isManagingPages else {
                manageMode = .select
                draggedReorderPageID = nil
                reorderTargetPageID = nil
                syncReorderDraftPages()
                return
            }

            manageMode = .select
            syncReorderDraftPages()
        }
        .alert("Delete Pages?", isPresented: $showsDeleteConfirmation) {
            Button("Cancel", role: .cancel) {
            }

            Button("Delete", role: .destructive) {
                revisedDocumentName = defaultRevisedName
                showsDeleteSaveDialog = true
            }
        } message: {
            let count = workflowController.context.selectedPages.count
            Text("Remove \(count) selected page\(count == 1 ? "" : "s") from this PDF?")
        }
        .overlay {
            if showsRenameDialog {
                ScanovaRenameOverlay(
                    title: "Rename PDF",
                    message: "Update the saved document name.",
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
            } else if showsSplitSaveDialog {
                ScanovaRenameOverlay(
                    title: "Save Split PDF",
                    message: "Name the new PDF created from the selected pages.",
                    saveTitle: "Save",
                    text: $splitDocumentName,
                    onCancel: {
                        showsSplitSaveDialog = false
                    },
                    onSave: {
                        workflowController.createDocumentFromSelection(
                            named: splitDocumentName.trimmingCharacters(in: .whitespacesAndNewlines)
                        )
                        showsSplitSaveDialog = false
                    }
                )
            } else if showsDeleteSaveDialog {
                ScanovaRenameOverlay(
                    title: "Save Revised PDF",
                    message: "Save the remaining pages as a new PDF and keep the original unchanged.",
                    saveTitle: "Save",
                    text: $revisedDocumentName,
                    onCancel: {
                        showsDeleteSaveDialog = false
                    },
                    onSave: {
                        workflowController.createDocumentRemovingSelection(
                            named: revisedDocumentName.trimmingCharacters(in: .whitespacesAndNewlines)
                        )
                        showsDeleteSaveDialog = false
                    }
                )
            } else if showsReorderSaveDialog {
                ScanovaRenameOverlay(
                    title: "Save Reordered PDF",
                    message: "Save the new page order as a separate PDF and keep the original unchanged.",
                    saveTitle: "Save",
                    text: $reorderedDocumentName,
                    onCancel: {
                        showsReorderSaveDialog = false
                    },
                    onSave: {
                        workflowController.createDocumentReorderingPages(
                            reorderDraftPages,
                            named: reorderedDocumentName.trimmingCharacters(in: .whitespacesAndNewlines)
                        )
                        showsReorderSaveDialog = false
                        manageMode = .select
                        draggedReorderPageID = nil
                        reorderTargetPageID = nil
                    }
                )
            }
        }
        .scanovaBackSwipe(isEnabled: viewerBackSwipeEnabled) {
            handleBackSwipe()
        }
    }

    private var viewerContent: some View {
        ZStack {
            Group {
                if let pdfData = workflowController.context.pdfData {
                    PDFKitPreview(
                        data: pdfData,
                        onPageTap: { _ in
                            withAnimation(.easeInOut(duration: 0.18)) {
                                isImmersiveReading.toggle()
                            }
                        },
                        onVisiblePageChanged: { _ in }
                    )
                } else {
                    RoundedRectangle(cornerRadius: 0, style: .continuous)
                        .fill(Color.white.opacity(0.92))
                        .overlay {
                            ProgressView()
                        }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea()

            if !isImmersiveReading {
                VStack {
                    viewerHeader
                        .frame(maxWidth: viewerChromeMaxWidth)
                        .padding(.horizontal, 26)
                        .padding(.top, 10)

                    Spacer()
                }
                .padding(.bottom, 108)
            }

            if !isImmersiveReading && !showsRenameDialog && !showsSplitSaveDialog && !showsDeleteSaveDialog && !showsReorderSaveDialog {
                VStack {
                    Spacer()
                    viewerBottomBar
                }
                .ignoresSafeArea(edges: .bottom)
            }
        }
    }

    private var selectionContent: some View {
        VStack(spacing: 0) {
            selectionHeader
                .padding(.horizontal, 16)
                .padding(.top, 8)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(alignment: .firstTextBaseline) {
                        ScanovaSectionTitle(manageMode == .select ? "Choose Pages" : "Drag to Reorder")

                        Spacer()

                        Text(selectionCountLabel)
                            .font(ScanovaTypography.button)
                            .foregroundStyle(ScanovaPalette.inkMuted)
                    }

                    LazyVGrid(columns: gridColumns, spacing: 16) {
                        ForEach(Array(managePages.enumerated()), id: \.element.id) { index, page in
                            if manageMode == .reorder {
                                reorderTile(for: page, index: index)
                            } else {
                                selectionTile(for: page, index: index)
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 18)
                .padding(.bottom, 140)
            }
        }
        .overlay(alignment: .bottom) {
            if !showsSplitSaveDialog && !showsDeleteSaveDialog && !showsReorderSaveDialog {
                ScanovaBottomBar {
                    if manageMode == .select {
                        HStack(spacing: 12) {
                            Button("Delete", action: beginDeleteFlow)
                                .buttonStyle(ScanovaSecondaryButtonStyle())
                                .disabled(workflowController.context.selectedPages.isEmpty)
                                .opacity(workflowController.context.selectedPages.isEmpty ? 0.45 : 1)

                            Button("Reorder", action: beginReorderMode)
                                .buttonStyle(ScanovaSecondaryButtonStyle())
                                .disabled(workflowController.context.pageCount < 2)
                                .opacity(workflowController.context.pageCount < 2 ? 0.45 : 1)

                            Button("Split", action: beginSplitFlow)
                                .buttonStyle(ScanovaPrimaryButtonStyle())
                                .disabled(workflowController.context.selectedPages.isEmpty)
                                .opacity(workflowController.context.selectedPages.isEmpty ? 0.45 : 1)
                        }
                    } else {
                        HStack(spacing: 12) {
                            Button("Cancel") {
                                cancelReorderMode()
                            }
                            .buttonStyle(ScanovaSecondaryButtonStyle())

                            Button("Save Order") {
                                reorderedDocumentName = defaultReorderedName
                                showsReorderSaveDialog = true
                            }
                            .buttonStyle(ScanovaPrimaryButtonStyle())
                            .disabled(!hasReorderChanges)
                            .opacity(hasReorderChanges ? 1 : 0.45)
                        }
                    }
                }
            }
        }
    }

    private var viewerHeader: some View {
        HStack(alignment: .center, spacing: 10) {
            Button("Back", action: workflowController.showRecentDocuments)
                .font(Font.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(ScanovaPalette.ink.opacity(0.92))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.14), in: Capsule(style: .continuous))
                .overlay {
                    Capsule(style: .continuous)
                        .stroke(Color.white.opacity(0.22), lineWidth: 0.9)
                }

            Button {
                draftDocumentName = workflowController.context.name
                showsRenameDialog = true
            } label: {
                HStack(alignment: .center, spacing: 8) {
                Text(workflowController.context.name)
                    .font(ScanovaTypography.sectionTitle)
                    .foregroundStyle(ScanovaPalette.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                        .allowsTightening(true)

                    Image(systemName: "pencil")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(ScanovaPalette.inkSoft)
                        .padding(4)
                        .background(Color.white.opacity(0.28), in: Circle())
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Rename document")
            .accessibilityValue(workflowController.context.name)

            Menu {
                ForEach(DocumentType.allCases, id: \.self) { type in
                    Button(appPreferences.displayName(for: type)) {
                        workflowController.updateDetectedType(type)
                    }
                }
            } label: {
                Text(appPreferences.displayName(for: workflowController.context.detectedType))
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
            .accessibilityLabel("Document type")
            .accessibilityValue(appPreferences.displayName(for: workflowController.context.detectedType))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(.ultraThinMaterial)

                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(Color.white.opacity(0.18))
            }
        )
        .overlay {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(Color.white.opacity(0.36), lineWidth: 1)
        }
        .shadow(color: Color.white.opacity(0.10), radius: 1, x: 0, y: 1)
        .shadow(color: Color.black.opacity(0.08), radius: 14, x: 0, y: 7)
    }

    private var viewerBottomBar: some View {
        ScanovaBottomBar {
            HStack(spacing: 12) {
                Button("Home", action: workflowController.showCaptureShell)
                    .buttonStyle(ScanovaSecondaryButtonStyle())

                Button("Manage") {
                    workflowController.startSelectionMode()
                }
                .buttonStyle(ScanovaPrimaryButtonStyle())
            }
        }
        .frame(maxWidth: viewerChromeMaxWidth)
        .padding(.horizontal, 26)
        .padding(.bottom, 14)
    }

    private var selectionHeader: some View {
        HStack(alignment: .center, spacing: 12) {
            Text("Manage Pages")
                .font(ScanovaTypography.heroTitle)
                .foregroundStyle(ScanovaPalette.ink)

            Spacer(minLength: 0)

            Button("Cancel") {
                isImmersiveReading = false
                cancelReorderMode()
                workflowController.endSelectionMode()
            }
            .buttonStyle(ScanovaGlassButtonStyle())
        }
    }

    private func selectionTile(for page: DocumentPage, index: Int) -> some View {
        let isSelected = workflowController.context.selectedPages.contains(index)

        return Button {
            workflowController.togglePageSelection(index)
        } label: {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(Color.white.opacity(0.76))
                    .overlay {
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .stroke(isSelected ? ScanovaPalette.accent : Color.white.opacity(0.5), lineWidth: isSelected ? 3 : 1)
                    }
                    .shadow(color: Color.black.opacity(0.05), radius: 16, x: 0, y: 8)

                Image(uiImage: page.image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(Color.white.opacity(0.86))
                    )
                    .padding(14)

                ZStack {
                    Circle()
                        .fill(isSelected ? ScanovaPalette.accent : Color.white.opacity(0.96))
                        .frame(width: 34, height: 34)

                    Text("\(index + 1)")
                        .font(ScanovaTypography.caption)
                        .foregroundStyle(isSelected ? Color.white : ScanovaPalette.ink)
                }
                .padding(14)
            }
            .frame(height: 240)
        }
        .buttonStyle(.plain)
    }

    private var isManagingPages: Bool {
        workflowController.currentStep == .selection
    }

    private var selectionCountLabel: String {
        if manageMode == .reorder {
            return hasReorderChanges ? "Unsaved order" : "\(reorderDraftPages.count) pages"
        }

        let count = workflowController.context.selectedPages.count
        return count == 0 ? "None selected" : "\(count) selected"
    }

    private var defaultSplitName: String {
        let baseName = workflowController.context.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return baseName.isEmpty ? "Split PDF" : "\(baseName) Split"
    }

    private var defaultRevisedName: String {
        let baseName = workflowController.context.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return baseName.isEmpty ? "Revised PDF" : "\(baseName) Revised"
    }

    private var defaultReorderedName: String {
        let baseName = workflowController.context.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return baseName.isEmpty ? "Reordered PDF" : "\(baseName) Reordered"
    }

    private var viewerBackSwipeEnabled: Bool {
        !showsRenameDialog &&
        !showsSplitSaveDialog &&
        !showsDeleteConfirmation &&
        !showsDeleteSaveDialog &&
        !showsReorderSaveDialog
    }

    private func handleBackSwipe() {
        if isManagingPages {
            isImmersiveReading = false
            cancelReorderMode()
            workflowController.endSelectionMode()
        } else if isImmersiveReading {
            withAnimation(.easeInOut(duration: 0.18)) {
                isImmersiveReading = false
            }
        } else {
            workflowController.showRecentDocuments()
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

    private var managePages: [DocumentPage] {
        manageMode == .reorder ? reorderDraftPages : workflowController.context.pages
    }

    private var hasReorderChanges: Bool {
        reorderDraftPages.map(\.id) != workflowController.context.pages.map(\.id)
    }

    private func syncReorderDraftPages() {
        reorderDraftPages = workflowController.context.pages
    }

    private func beginSplitFlow() {
        guard !workflowController.context.selectedPages.isEmpty else { return }
        guard subscriptionService.requirePremium(.split, router: router) else { return }
        splitDocumentName = defaultSplitName
        showsSplitSaveDialog = true
    }

    private func beginDeleteFlow() {
        guard !workflowController.context.selectedPages.isEmpty else { return }
        guard subscriptionService.requirePremium(.deletePages, router: router) else { return }
        showsDeleteConfirmation = true
    }

    private func beginReorderMode() {
        guard workflowController.context.pageCount > 1 else { return }
        if manageMode == .reorder { return }
        guard subscriptionService.requirePremium(.reorderPages, router: router) else { return }

        workflowController.clearPageSelection()
        syncReorderDraftPages()
        draggedReorderPageID = nil
        reorderTargetPageID = nil
        manageMode = .reorder
    }

    private func cancelReorderMode() {
        manageMode = .select
        draggedReorderPageID = nil
        reorderTargetPageID = nil
        syncReorderDraftPages()
    }

    private func manageModeButton(title: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(ScanovaTypography.button)
                .foregroundStyle(isActive ? .white : ScanovaPalette.ink)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    Capsule(style: .continuous)
                        .fill(isActive ? ScanovaPalette.accent : Color.white.opacity(0.78))
                )
                .overlay {
                    Capsule(style: .continuous)
                        .stroke(isActive ? ScanovaPalette.accent.opacity(0.2) : Color.white.opacity(0.5), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
    }

    private func reorderTile(for page: DocumentPage, index: Int) -> some View {
        let isDragged = draggedReorderPageID == page.id
        let isDropTarget = reorderTargetPageID == page.id && !isDragged

        return ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color.white.opacity(0.78))
                .overlay {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(isDropTarget ? ScanovaPalette.accent : Color.white.opacity(0.52), lineWidth: isDropTarget ? 3 : 1)
                }
                .shadow(color: Color.black.opacity(isDragged ? 0.10 : 0.05), radius: isDragged ? 22 : 16, x: 0, y: isDragged ? 14 : 8)

            Image(uiImage: page.image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Color.white.opacity(0.88))
                )
                .padding(14)

            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.96))
                    .frame(width: 34, height: 34)

                Text("\(index + 1)")
                    .font(ScanovaTypography.caption)
                    .foregroundStyle(ScanovaPalette.ink)
            }
            .padding(14)
        }
        .frame(height: 240)
        .scaleEffect(isDragged ? 1.03 : 1)
        .opacity(isDragged ? 0.88 : 1)
        .animation(.spring(response: 0.24, dampingFraction: 0.84), value: reorderDraftPages.map(\.id))
        .onDrag {
            draggedReorderPageID = page.id
            reorderTargetPageID = page.id
            return NSItemProvider(object: page.id.uuidString as NSString)
        }
        .onDrop(
            of: [UTType.plainText],
            delegate: ViewerReorderDropDelegate(
                pageID: page.id,
                pages: $reorderDraftPages,
                draggedPageID: $draggedReorderPageID,
                targetPageID: $reorderTargetPageID
            )
        )
    }
}

private struct ViewerReorderDropDelegate: DropDelegate {
    let pageID: UUID
    @Binding var pages: [DocumentPage]
    @Binding var draggedPageID: UUID?
    @Binding var targetPageID: UUID?

    func dropEntered(info: DropInfo) {
        guard let draggedPageID,
              draggedPageID != pageID,
              let fromIndex = pages.firstIndex(where: { $0.id == draggedPageID }),
              let toIndex = pages.firstIndex(where: { $0.id == pageID }) else { return }

        targetPageID = pageID

        if fromIndex != toIndex {
            withAnimation(.spring(response: 0.24, dampingFraction: 0.84)) {
                let movedPage = pages.remove(at: fromIndex)
                pages.insert(movedPage, at: toIndex)
            }
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        targetPageID = nil
        draggedPageID = nil
        return true
    }

    func dropExited(info: DropInfo) {
        if targetPageID == pageID {
            targetPageID = nil
        }
    }
}
