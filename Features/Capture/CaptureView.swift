import AVFoundation
import PhotosUI
import SwiftUI
import VisionKit

struct CaptureView: View {
    @EnvironmentObject private var accountService: AccountService
    @EnvironmentObject private var appPreferences: AppPreferences
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var subscriptionService: SubscriptionService
    @EnvironmentObject private var workflowController: WorkflowController

    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var isLoading = false
    @State private var isShowingDocumentCamera = false
    @State private var errorMessage: String?
    @State private var hasAttemptedAutoLaunch = false
    @State private var showcaseIndex = 0
    @State private var presentedDetailSheet: ScanovaSupportDetail?
    @State private var isShowingRenamePrompt = false
    @State private var isShowingManageTagsSheet = false
    @State private var isShowingSortDialog = false
    @State private var renameDraft = ""

    private let ingestionService = DocumentIngestionService()
    private let showcaseItems: [CaptureShowcaseItem] = [
        .init(
            title: "Scan Fast",
            message: "Scan, crop, rotate, and move into Preview.",
            eyebrow: "Fast Capture",
            accent: ScanovaPalette.accent,
            symbol: "bolt.badge.clock.fill",
            detail: "Free: scan, import, and clean up pages.",
            highlights: ["Scan", "Crop", "Rotate"]
        ),
        .init(
            title: "Mark It Clearly",
            message: "Add signatures, stamps, and shapes in Preview.",
            eyebrow: "Visual Editing",
            accent: ScanovaPalette.sky,
            symbol: "signature",
            detail: "Pro: mark up pages with precision.",
            highlights: ["Signature", "Stamp", "Shapes"]
        ),
        .init(
            title: "Save With Control",
            message: "Protect, compress, merge, and reorder with ease.",
            eyebrow: "Premium Tools",
            accent: ScanovaPalette.success,
            symbol: "lock.doc.fill",
            detail: "Pro: stronger save and export tools.",
            highlights: ["Protect", "Compress", "Reorder"]
        )
    ]

    var body: some View {
        ZStack {
            ScanovaScreenBackground()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    header

                    if let errorMessage {
                        errorBanner(message: errorMessage)
                    }

                    if showsDraftIntakeCard {
                        intakeCard
                    }

                    accountIdentitySurface
                    quickSettingsSurface

                    middleSurface
                        .frame(maxWidth: 336)
                        .frame(maxWidth: .infinity, alignment: .center)

                    settingsSurface
                        .padding(.top, 4)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 110)
            }

            if isShowingRenamePrompt {
                workspaceRenameOverlay
            }
        }
        .task {
            await subscriptionService.prepareStore()
        }
        .task {
            guard appPreferences.autoOpenScannerOnLaunch, !hasAttemptedAutoLaunch else { return }
            guard workflowController.currentStep == .capture, workflowController.context.pageCount == 0 else { return }
            hasAttemptedAutoLaunch = true
            try? await Task.sleep(for: .milliseconds(250))
            launchScanner()
        }
        .task(id: selectedPhotoItems) {
            await handlePhotoImport()
        }
        .task(id: workflowController.shouldAutoLaunchScanner) {
            guard workflowController.shouldAutoLaunchScanner, !hasAttemptedAutoLaunch else { return }
            hasAttemptedAutoLaunch = true
            workflowController.markAutoLaunchScannerHandled()
            try? await Task.sleep(for: .milliseconds(350))
            launchScanner()
        }
        .overlay {
            if isLoading {
                ZStack {
                    Color.black.opacity(0.08).ignoresSafeArea()
                    ProgressView("Importing…")
                        .padding()
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
            }
        }
        .sheet(isPresented: $isShowingDocumentCamera) {
            DocumentCameraSheet(
                onScan: handleDocumentScan,
                onCancel: handleDocumentCameraCancel,
                onError: handleDocumentCameraError
            )
            .ignoresSafeArea()
        }
        .sheet(item: $presentedDetailSheet) { detailSheet in
            ScanovaSupportDetailSheet(detail: detailSheet)
        }
        .sheet(isPresented: $isShowingManageTagsSheet) {
            ManageTagsSheet()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .confirmationDialog("Default Sort", isPresented: $isShowingSortDialog, titleVisibility: .visible) {
            ForEach(DocumentsSortPreference.allCases, id: \.self) { option in
                Button(option.title) {
                    appPreferences.updateDefaultDocumentsSort(option)
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            ScanovaPrimaryNavigationBar(
                activeDestination: .home,
                onSelectHome: workflowController.showCaptureShell,
                onSelectDocuments: workflowController.showRecentDocuments,
                onScan: launchScanner,
                isDocumentsDisabled: isLoading,
                isScanDisabled: isLoading
            )
        }
    }

    private var workspaceRenameOverlay: some View {
        ScanovaRenameOverlay(
            title: "Rename Workspace",
            message: "Choose the name shown at the top of your Scanova home.",
            fieldTitle: "Workspace name",
            text: $renameDraft,
            onCancel: {
                renameDraft = accountService.displayName
                isShowingRenamePrompt = false
            },
            onSave: {
                accountService.updateDisplayName(renameDraft)
                renameDraft = accountService.displayName
                isShowingRenamePrompt = false
            }
        )
        .transition(.opacity.combined(with: .scale(scale: 0.98)))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            ScanovaTitleBar(title: "Scanova") {
                PhotosPicker(selection: $selectedPhotoItems, maxSelectionCount: 20, matching: .images) {
                    Image(systemName: "photo.on.rectangle")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(ScanovaGlassIconButtonStyle())
                .disabled(isLoading)
                .accessibilityLabel("Import from Photos")
            }

            Text("Scan, organize, and export documents from one calm workspace.")
                .font(ScanovaTypography.supporting)
                .foregroundStyle(ScanovaPalette.inkMuted)
        }
    }

    private func errorBanner(message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)

            Text(message)
                .font(ScanovaTypography.supporting)
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            Color.white.opacity(0.72),
            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.red.opacity(0.18), lineWidth: 1)
        }
    }

    private var intakeCard: some View {
        ScanovaCard(accent: ScanovaPalette.success) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Pages ready")
                        .font(ScanovaTypography.sectionTitle)
                        .foregroundStyle(ScanovaPalette.ink)

                    Text("\(workflowController.context.pageCount) page\(workflowController.context.pageCount == 1 ? "" : "s") captured")
                        .font(ScanovaTypography.supporting)
                        .foregroundStyle(ScanovaPalette.inkMuted)
                }

                Spacer()

                Button("Open") {
                    workflowController.goToNextStep()
                }
                .buttonStyle(ScanovaGhostButtonStyle())
                .accessibilityLabel("Review captured pages")
            }
        }
    }

    private var showsDraftIntakeCard: Bool {
        workflowController.context.pageCount > 0 && workflowController.lastExportedPDFURL == nil
    }

    private var accountIdentitySurface: some View {
        Button {
            renameDraft = accountService.displayName
            isShowingRenamePrompt = true
        } label: {
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.white.opacity(0.92), ScanovaPalette.cloud],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 66, height: 66)

                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 32, weight: .medium))
                        .foregroundStyle(ScanovaPalette.ink)
                }
                .overlay {
                    Circle()
                        .stroke(Color.white.opacity(0.58), lineWidth: 1)
                }

                VStack(spacing: 4) {
                    Text("Workspace")
                        .font(ScanovaTypography.caption)
                        .foregroundStyle(ScanovaPalette.inkMuted)

                    HStack(spacing: 8) {
                        Text(accountService.displayName)
                            .font(ScanovaTypography.bodyEmphasis)
                            .foregroundStyle(ScanovaPalette.ink)
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)

                        Image(systemName: "pencil")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(ScanovaPalette.inkMuted)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                }
                .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 2)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Rename workspace")
        .accessibilityValue(accountService.displayName)
    }

    private var quickSettingsSurface: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(spacing: 8) {
                quickSettingTile(
                    title: "Tags",
                    value: "\(DocumentType.allCases.count + appPreferences.customTags.count) labels",
                    systemImage: "tag.fill",
                    tint: Color(red: 0.96, green: 0.57, blue: 0.28),
                    style: .wide
                ) {
                    isShowingManageTagsSheet = true
                }

                HStack(spacing: 8) {
                    quickSettingTile(
                        title: "Auto Naming",
                        value: appPreferences.autoNamingEnabled ? "Smart names on" : "Smart names off",
                        systemImage: "text.viewfinder",
                        tint: Color(red: 0.62, green: 0.50, blue: 0.95)
                    ) {
                        appPreferences.setAutoNamingEnabled(!appPreferences.autoNamingEnabled)
                        workflowController.setAutoNamingEnabled(appPreferences.autoNamingEnabled)
                    }

                    quickSettingTile(
                        title: "Scanner",
                        value: appPreferences.autoOpenScannerOnLaunch ? "Auto-open on" : "Auto-open off",
                        systemImage: "camera.aperture",
                        tint: Color(red: 0.99, green: 0.45, blue: 0.60)
                    ) {
                        appPreferences.setAutoOpenScannerOnLaunch(!appPreferences.autoOpenScannerOnLaunch)
                    }
                }

            }
        }
        .frame(maxWidth: 336)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var middleSurface: some View {
        VStack(alignment: .leading, spacing: 10) {
            Group {
                if subscriptionService.isSubscribed {
                    subscribedShellSurface
                } else {
                    showcaseCarouselSurface
                }
            }

            utilityActionRow
        }
    }

    private var utilityActionRow: some View {
        HStack(spacing: 8) {
            utilityChip(
                title: "Restore Purchase",
                systemImage: "arrow.clockwise",
                tint: Color(red: 0.13, green: 0.69, blue: 0.53),
                action: {
                    Task {
                        await subscriptionService.restorePurchases()
                    }
                }
            )
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var subscribedShellSurface: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Pro Active")
                        .font(ScanovaTypography.cardTitle)
                        .foregroundStyle(ScanovaPalette.ink)

                    Text("Merge, split, reorder, protect, compress, convert, and annotate documents with Pro tools.")
                        .font(ScanovaTypography.supporting)
                        .foregroundStyle(ScanovaPalette.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                Image(systemName: "checkmark.seal.fill")
                    .font(ScanovaTypography.bodyEmphasis)
                    .foregroundStyle(Color(red: 0.22, green: 0.55, blue: 1.0))
                    .padding(.top, 2)
            }

            HStack(spacing: 10) {
                Text("Pro Active")
                    .font(ScanovaTypography.caption)
                    .foregroundStyle(Color(red: 0.19, green: 0.46, blue: 0.94))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color(red: 0.23, green: 0.48, blue: 1.0).opacity(0.14))
                    )

                Spacer(minLength: 8)

                Button("Plans") {
                    router.showPaywall()
                }
                .buttonStyle(ScanovaGhostButtonStyle())
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .background(
            LinearGradient(
                colors: [
                    Color.white.opacity(0.94),
                    Color(red: 0.32, green: 0.59, blue: 1.0).opacity(0.13),
                    Color(red: 0.17, green: 0.82, blue: 0.73).opacity(0.08)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 30, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .stroke(Color.white.opacity(0.72), lineWidth: 1)
        }
        .shadow(color: Color(red: 0.28, green: 0.48, blue: 1.0).opacity(0.10), radius: 20, x: 0, y: 12)
    }

    private var showcaseCarouselSurface: some View {
        VStack(alignment: .leading, spacing: 14) {
            TabView(selection: $showcaseIndex) {
                ForEach(Array(showcaseItems.enumerated()), id: \.offset) { index, item in
                    showcaseCard(item: item)
                        .tag(index)
                        .padding(.horizontal, 2)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: 236)

            HStack(spacing: 8) {
                ForEach(showcaseItems.indices, id: \.self) { index in
                    Capsule(style: .continuous)
                        .fill(index == showcaseIndex ? ScanovaPalette.accentDark : Color.white.opacity(0.52))
                        .frame(width: index == showcaseIndex ? 20 : 8, height: 8)
                        .animation(.easeInOut(duration: 0.2), value: showcaseIndex)
                }

                Spacer()
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 4)
        }
        .padding(.vertical, 8)
        .background(
            LinearGradient(
                colors: [Color.white.opacity(0.40), Color.white.opacity(0.16)],
                startPoint: .top,
                endPoint: .bottom
            ),
            in: RoundedRectangle(cornerRadius: 34, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .stroke(Color.white.opacity(0.42), lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.04), radius: 18, x: 0, y: 10)
    }

    private var settingsSurface: some View {
        VStack(alignment: .leading, spacing: 14) {
            freeTierDetailsSurface
            footerInfoSurface
        }
        .frame(maxWidth: 336)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var freeTierDetailsSurface: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("The free tier handles core scanning and reading. Pro is reserved for advanced editing, protection, export, and page tools.")
                .font(ScanovaTypography.supporting)
                .foregroundStyle(ScanovaPalette.inkMuted)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 12) {
                Text("Included in Free")
                    .font(ScanovaTypography.sectionTitle)
                    .foregroundStyle(ScanovaPalette.ink)

                freeFeatureBullet("Camera scan and document import")
                freeFeatureBullet("OCR, smart naming, and document understanding")
                freeFeatureBullet("Crop, rotate, rename, and save PDFs")
                freeFeatureBullet("Read and manage saved documents")
            }
            .padding(18)
            .background(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.92),
                        Color(red: 0.17, green: 0.82, blue: 0.73).opacity(0.10)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 28, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(Color.white.opacity(0.58), lineWidth: 1)
            }
        }
    }

    private var footerInfoSurface: some View {
        VStack(alignment: .center, spacing: 12) {
            HStack(spacing: 14) {
                footerLinkButton(title: "Privacy", detail: .privacy)
                footerDivider
                footerLinkButton(title: "Terms", detail: .terms)
                footerDivider
                footerLinkButton(title: "Help", detail: .support)
            }
            .frame(maxWidth: .infinity)

            Text("Version \(versionLabel)")
                .font(ScanovaTypography.caption)
                .foregroundStyle(ScanovaPalette.inkMuted)
        }
        .padding(.horizontal, 8)
        .padding(.top, 2)
        .padding(.bottom, 8)
    }

    private var versionLabel: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    private var footerDivider: some View {
        Capsule(style: .continuous)
            .fill(Color.white.opacity(0.55))
            .frame(width: 4, height: 4)
    }

    private func footerLinkButton(title: String, detail: ScanovaSupportDetail) -> some View {
        Button(title) {
            presentedDetailSheet = detail
        }
        .buttonStyle(.plain)
        .font(ScanovaTypography.supporting)
        .foregroundStyle(ScanovaPalette.inkSoft)
    }

    private func utilityChip(title: String, systemImage: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            utilityChipLabel(title: title, systemImage: systemImage, tint: tint)
        }
        .buttonStyle(.plain)
    }

    private func quickSettingTile(
        title: String,
        value: String,
        systemImage: String,
        tint: Color,
        style: QuickSettingTileStyle = .compact,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Group {
                if style == .wide {
                    HStack(spacing: 12) {
                        quickSettingIcon(systemImage: systemImage, tint: tint)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(title)
                                .font(ScanovaTypography.supporting)
                                .foregroundStyle(ScanovaPalette.ink)

                            Text(value)
                                .font(ScanovaTypography.caption)
                                .foregroundStyle(ScanovaPalette.inkMuted)
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(ScanovaPalette.inkMuted.opacity(0.82))
                    }
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        quickSettingIcon(systemImage: systemImage, tint: tint)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(title)
                                .font(ScanovaTypography.caption)
                                .foregroundStyle(ScanovaPalette.inkMuted)

                            Text(value)
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundStyle(ScanovaPalette.ink)
                                .lineLimit(2)
                                .minimumScaleFactor(0.82)
                        }
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                LinearGradient(
                    colors: [Color.white.opacity(0.92), tint.opacity(0.10)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 22, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.white.opacity(0.7), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    private func quickSettingIcon(systemImage: String, tint: Color) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: 30, height: 30)
            .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func utilityChipLabel(title: String, systemImage: String, tint: Color) -> some View {
        Label(title, systemImage: systemImage)
            .font(ScanovaTypography.supporting)
            .foregroundStyle(tint.opacity(0.96))
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(
                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.96),
                                tint.opacity(0.20)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay {
                Capsule(style: .continuous)
                    .stroke(tint.opacity(0.24), lineWidth: 1)
            }
            .shadow(color: tint.opacity(0.08), radius: 10, x: 0, y: 4)
    }

    private func freeFeatureBullet(_ title: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Color(red: 0.13, green: 0.69, blue: 0.53))
                .padding(.top, 1)

            Text(title)
                .font(ScanovaTypography.supporting)
                .foregroundStyle(ScanovaPalette.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func showcaseCard(item: CaptureShowcaseItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 7) {
                    Text(item.eyebrow)
                        .font(ScanovaTypography.caption)
                        .foregroundStyle(item.accent.opacity(0.92))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.white.opacity(0.26))
                        )

                    Text(item.title)
                        .font(Font.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(ScanovaPalette.ink)

                    Text(item.message)
                        .font(ScanovaTypography.supporting)
                        .foregroundStyle(ScanovaPalette.inkMuted)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                showcaseArtwork(for: item)
            }

            HStack(spacing: 6) {
                ForEach(item.highlights, id: \.self) { highlight in
                    Text(highlight)
                        .font(ScanovaTypography.caption)
                        .foregroundStyle(ScanovaPalette.inkSoft)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.white.opacity(0.58))
                        )
                }
            }

            HStack(alignment: .bottom, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("With Pro")
                        .font(ScanovaTypography.caption)
                        .foregroundStyle(ScanovaPalette.inkSoft)

                    Text(item.detail)
                        .font(ScanovaTypography.caption)
                        .foregroundStyle(ScanovaPalette.inkMuted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.92)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Button("Try Pro") {
                    router.showPaywall()
                }
                .font(ScanovaTypography.button)
                .foregroundStyle(.white)
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(
                    Capsule(style: .continuous)
                        .fill(ScanovaPalette.accent)
                )
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            LinearGradient(
                colors: [
                    Color.white.opacity(0.92),
                    item.accent.opacity(0.13),
                    Color.white.opacity(0.58)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 30, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .stroke(Color.white.opacity(0.65), lineWidth: 1)
        }
        .shadow(color: item.accent.opacity(0.10), radius: 22, x: 0, y: 10)
    }

    private func showcaseArtwork(for item: CaptureShowcaseItem) -> some View {
        ZStack {
            Circle()
                .fill(item.accent.opacity(0.12))
                .frame(width: 64, height: 64)
                .blur(radius: 1)

            Circle()
                .fill(Color.white.opacity(0.54))
                .frame(width: 46, height: 46)

            Image(systemName: item.symbol)
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(item.accent)

            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.32))
                .frame(width: 20, height: 20)
                .overlay {
                    Image(systemName: "sparkles")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(item.accent.opacity(0.9))
                }
                .offset(x: 20, y: 20)
        }
    }

    @MainActor
    private func handlePhotoImport() async {
        guard !selectedPhotoItems.isEmpty else { return }

        isLoading = true
        defer {
            isLoading = false
            selectedPhotoItems = []
        }

        do {
            let imported = try await ingestionService.importPhotos(from: selectedPhotoItems)
            errorMessage = nil
            workflowController.ingest(imported)
        } catch {
            let importError = error as? LocalizedError
            errorMessage = importError?.errorDescription ?? error.localizedDescription
            workflowController.updateCaptureStatus("Photo import failed. Try another selection.")
        }
    }

    private func launchScanner() {
        errorMessage = nil
        workflowController.markAutoLaunchScannerHandled()

        guard VNDocumentCameraViewController.isSupported else {
            workflowController.updateCaptureStatus("Scanner unavailable on this device.")
            errorMessage = "Document scanning is not available on this device."
            return
        }

        isShowingDocumentCamera = true
    }

    private func handleDocumentScan(_ images: [UIImage]) {
        isShowingDocumentCamera = false

        do {
            let imported = try ingestionService.importScannedImages(images)
            workflowController.updateCaptureStatus("Scanned \(images.count) page\(images.count == 1 ? "" : "s").")
            workflowController.ingest(imported)
        } catch {
            let importError = error as? LocalizedError
            errorMessage = importError?.errorDescription ?? error.localizedDescription
            workflowController.updateCaptureStatus("Scan failed. Try again.")
        }
    }

    private func handleDocumentCameraCancel() {
        isShowingDocumentCamera = false
        workflowController.showCaptureShell()
    }

    private func handleDocumentCameraError(_ error: Error) {
        isShowingDocumentCamera = false
        errorMessage = friendlyCameraErrorMessage(for: error)
        workflowController.updateCaptureStatus("Scan failed. Try again.")
    }

    private func friendlyCameraErrorMessage(for error: Error) -> String {
        let nsError = error as NSError

        if nsError.domain == AVFoundationErrorDomain {
            return "Could not open the camera. Try again."
        }

        if let localizedError = error as? LocalizedError,
           let description = localizedError.errorDescription,
           !description.isEmpty {
            return description
        }

        return "Could not open the scanner. Try again."
    }
}

private struct CaptureShowcaseItem {
    let title: String
    let message: String
    let eyebrow: String
    let accent: Color
    let symbol: String
    let detail: String
    let highlights: [String]
}

private enum QuickSettingTileStyle {
    case compact
    case wide
}

private struct ManageTagsSheet: View {
    private enum EditTarget: Identifiable {
        case builtIn(DocumentType)
        case custom(Int)
        case addCustom

        var id: String {
            switch self {
            case let .builtIn(type):
                return "builtIn-\(type.rawValue)"
            case let .custom(index):
                return "custom-\(index)"
            case .addCustom:
                return "addCustom"
            }
        }
    }

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appPreferences: AppPreferences

    @State private var editTarget: EditTarget?
    @State private var tagDraft = ""

    var body: some View {
        ZStack {
            ScanovaScreenBackground()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    ScanovaTitleBar(title: "Manage Tags") {
                        Button("Done") {
                            dismiss()
                        }
                        .buttonStyle(ScanovaGlassButtonStyle())
                    }

                    ScanovaCard(accent: ScanovaPalette.accent) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("System Tags")
                                .font(ScanovaTypography.sectionTitle)
                                .foregroundStyle(ScanovaPalette.ink)

                            Text("These tags still power Scanova’s smart detection. You can rename how they appear in the app.")
                                .font(ScanovaTypography.supporting)
                                .foregroundStyle(ScanovaPalette.inkMuted)

                            ForEach(DocumentType.allCases, id: \.self) { type in
                                tagRow(
                                    title: appPreferences.displayName(for: type),
                                    subtitle: "System tag",
                                    onEdit: {
                                        tagDraft = appPreferences.displayName(for: type)
                                        editTarget = .builtIn(type)
                                    }
                                )
                            }
                        }
                    }

                    ScanovaCard(accent: ScanovaPalette.sky) {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Custom Tags")
                                    .font(ScanovaTypography.sectionTitle)
                                    .foregroundStyle(ScanovaPalette.ink)

                                Spacer()

                                Button {
                                    tagDraft = ""
                                    editTarget = .addCustom
                                } label: {
                                    Label("Add Tag", systemImage: "plus")
                                }
                                .buttonStyle(ScanovaGhostButtonStyle())
                            }

                            if appPreferences.customTags.isEmpty {
                                Text("Add your own labels for the kinds of documents you use most.")
                                    .font(ScanovaTypography.supporting)
                                    .foregroundStyle(ScanovaPalette.inkMuted)
                            } else {
                                ForEach(Array(appPreferences.customTags.enumerated()), id: \.offset) { index, tag in
                                    tagRow(
                                        title: tag,
                                        subtitle: "Custom tag",
                                        onEdit: {
                                            tagDraft = tag
                                            editTarget = .custom(index)
                                        },
                                        onDelete: {
                                            appPreferences.deleteCustomTags(at: IndexSet(integer: index))
                                        }
                                    )
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 32)
            }
        }
        .overlay {
            if editTarget != nil {
                ScanovaRenameOverlay(
                    title: isAddingCustomTag ? "Add Custom Tag" : "Rename Tag",
                    message: isAddingCustomTag
                        ? "Create a new custom tag for the documents you use most."
                        : "Choose the label you want Scanova to show in the app.",
                    fieldTitle: "Tag name",
                    saveTitle: isAddingCustomTag ? "Add" : "Save",
                    text: $tagDraft,
                    onCancel: {
                        editTarget = nil
                    },
                    onSave: saveTagChanges
                )
            }
        }
    }

    private var isAddingCustomTag: Bool {
        if case .addCustom = editTarget {
            return true
        }
        return false
    }

    @ViewBuilder
    private func tagRow(
        title: String,
        subtitle: String,
        onEdit: @escaping () -> Void,
        onDelete: (() -> Void)? = nil
    ) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(ScanovaTypography.bodyEmphasis)
                    .foregroundStyle(ScanovaPalette.ink)

                Text(subtitle)
                    .font(ScanovaTypography.caption)
                    .foregroundStyle(ScanovaPalette.inkMuted)
            }

            Spacer()

            if let onDelete {
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(ScanovaGlassIconButtonStyle())
                .accessibilityLabel("Delete tag")
            }

            Button(action: onEdit) {
                Image(systemName: "pencil")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(ScanovaGlassIconButtonStyle())
            .accessibilityLabel("Edit tag")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.white.opacity(0.58), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func saveTagChanges() {
        guard let editTarget else { return }

        switch editTarget {
        case let .builtIn(type):
            appPreferences.updateDisplayName(tagDraft, for: type)
        case let .custom(index):
            appPreferences.renameCustomTag(at: index, to: tagDraft)
        case .addCustom:
            appPreferences.addCustomTag(tagDraft)
        }

        self.editTarget = nil
    }
}
