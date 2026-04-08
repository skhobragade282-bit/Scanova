import SwiftUI

enum ScanovaTypography {
    static let heroTitle = Font.system(size: 30, weight: .bold, design: .rounded)
    static let screenTitle = Font.system(size: 20, weight: .semibold, design: .rounded)
    static let cardTitle = Font.system(size: 21, weight: .semibold, design: .rounded)
    static let sectionTitle = Font.system(size: 19, weight: .bold, design: .rounded)
    static let body = Font.system(size: 16, weight: .regular)
    static let bodyEmphasis = Font.system(size: 16, weight: .semibold)
    static let supporting = Font.system(size: 14, weight: .medium)
    static let caption = Font.system(size: 12, weight: .semibold)
    static let chip = Font.system(size: 15, weight: .semibold, design: .rounded)
    static let button = Font.system(size: 17, weight: .semibold, design: .rounded)
}

struct WorkflowHeader: View {
    enum Style {
        case standard
        case titleOnly
    }

    let eyebrow: String
    let title: String
    let description: String
    let style: Style

    init(eyebrow: String, title: String, description: String, style: Style = .standard) {
        self.eyebrow = eyebrow
        self.title = title
        self.description = description
        self.style = style
    }

    var body: some View {
        VStack(alignment: .leading, spacing: style == .titleOnly ? 0 : 8) {
            if style == .standard {
                Text(eyebrow.uppercased())
                    .font(.caption.weight(.bold))
                    .tracking(1.0)
                    .foregroundStyle(ScanovaPalette.inkSoft)
            }

            Text(title)
                .font(style == .titleOnly ? ScanovaTypography.heroTitle : .system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(ScanovaPalette.ink)

            if style == .standard {
                Text(description)
                    .font(ScanovaTypography.supporting)
                    .foregroundStyle(ScanovaPalette.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct ScanovaTitleBar<Trailing: View>: View {
    let title: String
    @ViewBuilder let trailing: Trailing

    init(title: String, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            Text(title)
                .font(ScanovaTypography.heroTitle)
                .foregroundStyle(ScanovaPalette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            Spacer(minLength: 16)

            HStack(spacing: 10) {
                trailing
            }
            .fixedSize(horizontal: true, vertical: false)
        }
    }
}

struct ScanovaCard<Content: View>: View {
    let accent: Color
    @ViewBuilder let content: Content

    init(accent: Color = ScanovaPalette.accent, @ViewBuilder content: () -> Content) {
        self.accent = accent
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            content
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [Color.white.opacity(0.88), accent.opacity(0.10), Color.white.opacity(0.55)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 28, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [Color.white.opacity(0.9), accent.opacity(0.16)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        }
        .shadow(color: Color.black.opacity(0.04), radius: 20, x: 0, y: 10)
    }
}

struct ScanovaScreenBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [ScanovaPalette.background, Color.white, ScanovaPalette.mist],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            Circle()
                .fill(ScanovaPalette.accent.opacity(0.10))
                .frame(width: 320, height: 320)
                .blur(radius: 40)
                .offset(x: 120, y: -260)

            Circle()
                .fill(ScanovaPalette.sky.opacity(0.16))
                .frame(width: 240, height: 240)
                .blur(radius: 35)
                .offset(x: -140, y: 280)
        }
        .allowsHitTesting(false)
    }
}

struct ScanovaSectionTitle: View {
    let title: String
    let subtitle: String?

    init(_ title: String, subtitle: String? = nil) {
        self.title = title
        self.subtitle = subtitle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(ScanovaTypography.sectionTitle)
                .foregroundStyle(ScanovaPalette.ink)

            if let subtitle {
                Text(subtitle)
                    .font(ScanovaTypography.supporting)
                    .foregroundStyle(ScanovaPalette.inkMuted)
            }
        }
    }
}

struct ScanovaBottomBar<Content: View>: View {
    @ViewBuilder let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(8)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .fill(.ultraThinMaterial)

                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color.white.opacity(0.18), Color.white.opacity(0.06)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
            )
            .overlay {
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .stroke(Color.white.opacity(0.42), lineWidth: 1)
            }
            .shadow(color: Color.white.opacity(0.10), radius: 1, x: 0, y: 1)
            .shadow(color: Color.black.opacity(0.06), radius: 18, x: 0, y: 10)
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 10)
    }
}

enum ScanovaPrimaryDestination {
    case home
    case documents
}

struct ScanovaPrimaryNavigationBar: View {
    let activeDestination: ScanovaPrimaryDestination
    let onSelectHome: () -> Void
    let onSelectDocuments: () -> Void
    let onScan: () -> Void
    var isHomeDisabled: Bool = false
    var isDocumentsDisabled: Bool = false
    var isScanDisabled: Bool = false

    var body: some View {
        ZStack(alignment: .top) {
            HStack(spacing: 0) {
                navigationItem(
                    title: "Home",
                    symbol: activeDestination == .home ? "house.fill" : "house",
                    isActive: activeDestination == .home,
                    action: onSelectHome
                )
                .disabled(isHomeDisabled)

                Spacer(minLength: 92)

                navigationItem(
                    title: "Docs",
                    symbol: activeDestination == .documents ? "doc.text.fill" : "doc.text",
                    isActive: activeDestination == .documents,
                    action: onSelectDocuments
                )
                .disabled(isDocumentsDisabled)
            }
            .padding(.horizontal, 18)
            .padding(.top, 22)
            .padding(.bottom, 10)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(.regularMaterial)

                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color.white.opacity(0.14), Color.white.opacity(0.04)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                }
            )
            .overlay {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(Color.white.opacity(0.38), lineWidth: 1)
            }
            .shadow(color: Color.black.opacity(0.08), radius: 18, x: 0, y: 10)

            Button(action: onScan) {
                VStack(spacing: 6) {
                    Image(systemName: "camera.viewfinder")
                        .font(.system(size: 21, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 62, height: 62)
                        .background(
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [ScanovaPalette.accent, ScanovaPalette.accentDark],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        )
                        .overlay {
                            Circle()
                                .stroke(Color.white.opacity(0.42), lineWidth: 1)
                        }
                        .shadow(color: ScanovaPalette.accent.opacity(0.20), radius: 14, x: 0, y: 9)
                        .shadow(color: Color.black.opacity(0.08), radius: 12, x: 0, y: 6)

                    Text("Scan")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(ScanovaPalette.inkSoft)
                }
                .frame(width: 84)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isScanDisabled)
            .offset(y: -18)
            .accessibilityLabel("Scan document")
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 8)
    }

    private func navigationItem(
        title: String,
        symbol: String,
        isActive: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.system(size: 18, weight: isActive ? .semibold : .medium))
                    .frame(height: 20)

                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(isActive ? ScanovaPalette.ink : ScanovaPalette.inkSoft)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(isActive ? Color.white.opacity(0.68) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }
}

struct ScanovaBottomTabButtonStyle: ButtonStyle {
    let isActive: Bool

    init(isActive: Bool = false) {
        self.isActive = isActive
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold, design: .rounded))
            .foregroundStyle(isActive ? ScanovaPalette.accentDark : ScanovaPalette.ink)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                Capsule(style: .continuous)
                    .fill(
                        isActive
                            ? AnyShapeStyle(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.92), ScanovaPalette.accentSoft.opacity(0.94)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            : AnyShapeStyle(.ultraThinMaterial)
                    )
            )
            .overlay {
                Capsule(style: .continuous)
                    .stroke(
                        isActive ? ScanovaPalette.accent.opacity(0.32) : Color.white.opacity(0.35),
                        lineWidth: 1
                    )
            }
            .shadow(color: Color.white.opacity(isActive ? 0.18 : 0.08), radius: 1, x: 0, y: 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.92 : 1)
    }
}

struct ScanovaPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(ScanovaTypography.button)
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.82)
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background(
                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [ScanovaPalette.accent, ScanovaPalette.accentDark],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.92 : 1)
    }
}

struct ScanovaSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(ScanovaTypography.button)
            .foregroundStyle(ScanovaPalette.ink)
            .lineLimit(1)
            .minimumScaleFactor(0.82)
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background(
                Capsule(style: .continuous)
                    .fill(ScanovaPalette.cloud.opacity(configuration.isPressed ? 0.72 : 0.96))
            )
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
    }
}

struct ScanovaCompactSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(ScanovaTypography.button)
            .foregroundStyle(ScanovaPalette.ink)
            .lineLimit(1)
            .minimumScaleFactor(0.82)
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .background(
                Capsule(style: .continuous)
                    .fill(ScanovaPalette.cloud.opacity(configuration.isPressed ? 0.72 : 0.96))
            )
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
    }
}

struct ScanovaGhostButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(ScanovaPalette.inkSoft)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                Capsule(style: .continuous)
                    .fill(ScanovaPalette.cloud.opacity(configuration.isPressed ? 0.7 : 1))
            )
    }
}

struct ScanovaGlassButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(ScanovaTypography.button)
            .foregroundStyle(ScanovaPalette.ink)
            .lineLimit(1)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial, in: Capsule(style: .continuous))
            .overlay {
                Capsule(style: .continuous)
                    .stroke(Color.white.opacity(0.35), lineWidth: 1)
            }
            .fixedSize(horizontal: true, vertical: false)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.92 : 1)
    }
}

struct ScanovaGlassIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(ScanovaPalette.ink)
            .frame(width: 52, height: 52)
            .background(.ultraThinMaterial, in: Circle())
            .overlay {
                Circle()
                    .stroke(Color.white.opacity(0.35), lineWidth: 1)
            }
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.92 : 1)
    }
}

enum ScanovaSupportDetail: String, Identifiable {
    case privacy
    case terms
    case support

    struct Section: Identifiable {
        let title: String
        let points: [String]

        var id: String { title }
    }

    var id: String { rawValue }

    var title: String {
        switch self {
        case .privacy:
            return "Privacy Policy"
        case .terms:
            return "Terms of Use"
        case .support:
            return "Support"
        }
    }

    var bodyText: String {
        switch self {
        case .privacy:
            return "Scanova keeps core document understanding on-device by default. Imported files, OCR results, and exports remain in app-managed storage unless you explicitly share them elsewhere."
        case .terms:
            return "The free tier includes scanning, OCR, refinement, and export. Premium is reserved for advanced export, security, and organization features."
        case .support:
            return "Use this guide to scan, edit, save, organize, and upgrade with confidence."
        }
    }

    var subtitle: String {
        switch self {
        case .privacy:
            return "How Scanova handles your documents."
        case .terms:
            return "The free and premium product boundary."
        case .support:
            return "Learn how each Scanova workflow works."
        }
    }

    var icon: String {
        switch self {
        case .privacy:
            return "hand.raised"
        case .terms:
            return "doc.text"
        case .support:
            return "questionmark.circle"
        }
    }

    var sections: [Section] {
        switch self {
        case .privacy, .terms:
            return []
        case .support:
            return [
                Section(
                    title: "Capture and Import",
                    points: [
                        "Use the camera button on Home to scan with the document scanner.",
                        "Tap Photos to import images from your library.",
                        "Use the Files button in Documents to bring in PDFs or images from the Files app.",
                        "When Auto Naming is on, Scanova suggests a smart document name automatically."
                    ]
                ),
                Section(
                    title: "Preview Editing",
                    points: [
                        "In Preview you can crop, rotate, add pages, delete pages, and reset edits.",
                        "Tap a page first before using page-specific tools like crop or insert.",
                        "Save stays pinned as the main action, while the tool strip lets you scroll through editing options."
                    ]
                ),
                Section(
                    title: "Insert Signature, Stamp, and Shapes",
                    points: [
                        "Choose Signature to draw one, pick one from Photos, use Files, or reuse your recent signature.",
                        "Choose Stamp to add built-in marks such as Approved, Paid, Received, or Confidential.",
                        "Choose Shapes to add a rectangle, circle, or arrow.",
                        "After choosing an insert tool, drag to move it, pinch to resize, twist to rotate, then tap Apply."
                    ]
                ),
                Section(
                    title: "Save and Export",
                    points: [
                        "Tap Save in Preview to open the export options page.",
                        "You can save a standard PDF, compress the PDF, protect it with a password, or combine both options.",
                        "Compression shows the current file size and an estimated output size before saving.",
                        "Protected PDFs will ask for the password when they are opened later."
                    ]
                ),
                Section(
                    title: "Documents and Viewer",
                    points: [
                        "Documents shows saved PDFs with their date and file size.",
                        "Open any document to read it in Viewer.",
                        "Use Manage Pages to split, delete, or reorder pages and save a new revised copy."
                    ]
                ),
                Section(
                    title: "Premium Features",
                    points: [
                        "Scanova Pro unlocks compress, password protection, merge, split, delete pages, reorder pages, convert to images, signature tools, stamps, and shapes.",
                        "Use Restore Purchases if you already bought Pro with the same Apple account.",
                        "The paywall will show the annual free trial only when StoreKit says your account is eligible."
                    ]
                )
            ]
        }
    }
}

struct ScanovaSupportDetailSheet: View {
    let detail: ScanovaSupportDetail

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    supportHeader

                    if detail.sections.isEmpty {
                        Text(detail.bodyText)
                            .font(.body)
                            .foregroundStyle(ScanovaPalette.inkMuted)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        ForEach(detail.sections) { section in
                            supportSectionCard(section)
                        }
                    }
                }
                .padding(20)
            }
            .background {
                ScanovaScreenBackground()
            }
            .navigationTitle(detail.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .buttonStyle(ScanovaGhostButtonStyle())
                }
            }
        }
    }

    private var supportHeader: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: detail.icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(ScanovaPalette.accent)
                .frame(width: 42, height: 42)
                .background(
                    Circle()
                        .fill(ScanovaPalette.accentSoft.opacity(0.92))
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(detail.subtitle)
                    .font(ScanovaTypography.bodyEmphasis)
                    .foregroundStyle(ScanovaPalette.ink)

                Text(detail.bodyText)
                    .font(ScanovaTypography.supporting)
                    .foregroundStyle(ScanovaPalette.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(18)
        .background(
            Color.white.opacity(0.70),
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.42), lineWidth: 1)
        }
    }

    private func supportSectionCard(_ section: ScanovaSupportDetail.Section) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(section.title)
                .font(ScanovaTypography.sectionTitle)
                .foregroundStyle(ScanovaPalette.ink)

            VStack(alignment: .leading, spacing: 10) {
                ForEach(section.points, id: \.self) { point in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(ScanovaPalette.success)
                            .padding(.top, 2)

                        Text(point)
                            .font(ScanovaTypography.supporting)
                            .foregroundStyle(ScanovaPalette.inkMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(18)
        .background(
            Color.white.opacity(0.74),
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.46), lineWidth: 1)
        }
    }
}

struct ScanovaRenameOverlay: View {
    let title: String
    let message: String
    let fieldTitle: String
    let saveTitle: String
    let isSecure: Bool
    @Binding var text: String
    let onCancel: () -> Void
    let onSave: () -> Void

    @FocusState private var isTextFieldFocused: Bool

    init(
        title: String,
        message: String,
        fieldTitle: String = "Document Name",
        saveTitle: String = "Save",
        isSecure: Bool = false,
        text: Binding<String>,
        onCancel: @escaping () -> Void,
        onSave: @escaping () -> Void
    ) {
        self.title = title
        self.message = message
        self.fieldTitle = fieldTitle
        self.saveTitle = saveTitle
        self.isSecure = isSecure
        self._text = text
        self.onCancel = onCancel
        self.onSave = onSave
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.10)
                .ignoresSafeArea()
                .onTapGesture {
                    isTextFieldFocused = false
                }

            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(title)
                        .font(ScanovaTypography.cardTitle)
                        .foregroundStyle(ScanovaPalette.ink)

                    Text(message)
                        .font(ScanovaTypography.supporting)
                        .foregroundStyle(ScanovaPalette.inkMuted)
                }

                Group {
                    if isSecure {
                        SecureField(fieldTitle, text: $text)
                    } else {
                        TextField(fieldTitle, text: $text)
                    }
                }
                .font(ScanovaTypography.body)
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.white.opacity(0.55))
                )
                .focused($isTextFieldFocused)

                HStack(spacing: 12) {
                    Button("Cancel", action: onCancel)
                        .buttonStyle(ScanovaSecondaryButtonStyle())

                    Button(saveTitle, action: onSave)
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
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isTextFieldFocused = true
            }
        }
    }
}

private struct ScanovaBackSwipeModifier: ViewModifier {
    let isEnabled: Bool
    let edgeWidth: CGFloat
    let minimumTranslation: CGFloat
    let onBack: () -> Void

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    Color.clear
                        .frame(width: min(edgeWidth, proxy.size.width), height: proxy.size.height)
                        .contentShape(Rectangle())
                        .highPriorityGesture(
                            DragGesture(minimumDistance: 12)
                                .onEnded { value in
                                    guard isEnabled else { return }
                                    guard value.startLocation.x <= edgeWidth + 4 else { return }
                                    guard value.translation.width >= minimumTranslation else { return }
                                    guard value.translation.width > abs(value.translation.height) else { return }
                                    onBack()
                                }
                        )
                }
                .ignoresSafeArea()
            }
    }
}

extension View {
    func scanovaBackSwipe(
        isEnabled: Bool = true,
        edgeWidth: CGFloat = 28,
        minimumTranslation: CGFloat = 72,
        onBack: @escaping () -> Void
    ) -> some View {
        modifier(
            ScanovaBackSwipeModifier(
                isEnabled: isEnabled,
                edgeWidth: edgeWidth,
                minimumTranslation: minimumTranslation,
                onBack: onBack
            )
        )
    }
}

enum ScanovaPalette {
    static let accent = Color(red: 0.10, green: 0.48, blue: 0.94)
    static let accentDark = Color(red: 0.05, green: 0.34, blue: 0.79)
    static let accentSoft = Color(red: 0.89, green: 0.95, blue: 1.0)
    static let background = Color(red: 0.97, green: 0.98, blue: 1.0)
    static let mist = Color(red: 0.95, green: 0.97, blue: 1.0)
    static let sky = Color(red: 0.78, green: 0.89, blue: 1.0)
    static let cloud = Color(red: 0.93, green: 0.95, blue: 0.98)
    static let line = Color.black.opacity(0.08)
    static let ink = Color(red: 0.08, green: 0.10, blue: 0.16)
    static let inkSoft = Color(red: 0.26, green: 0.31, blue: 0.40)
    static let inkMuted = Color(red: 0.40, green: 0.45, blue: 0.54)
    static let success = Color(red: 0.18, green: 0.62, blue: 0.40)
}
