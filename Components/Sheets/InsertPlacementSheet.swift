import SwiftUI
import UIKit

struct InsertPlacementSheet: View {
    let title: String
    let pageImage: UIImage
    let overlayImage: UIImage
    let onCancel: () -> Void
    let onApply: (InsertOverlayPlacement) -> Void

    @State private var normalizedCenter = CGPoint(x: 0.5, y: 0.5)
    @State private var normalizedWidth: CGFloat = 0.32
    @State private var rotation: CGFloat = 0
    @State private var dragStartCenter = CGPoint(x: 0.5, y: 0.5)
    @State private var scaleStartWidth: CGFloat = 0.32
    @State private var rotationStart: CGFloat = 0

    private var overlayAspectRatio: CGFloat {
        guard overlayImage.size.height > 0 else { return 1 }
        return overlayImage.size.width / overlayImage.size.height
    }

    private var pageAspectRatio: CGFloat {
        guard pageImage.size.height > 0 else { return 1 }
        return pageImage.size.width / pageImage.size.height
    }

    private var normalizedHeight: CGFloat {
        (normalizedWidth / overlayAspectRatio) * pageAspectRatio
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                ScanovaScreenBackground()
                    .ignoresSafeArea()

                VStack(spacing: 6) {
                    GeometryReader { geometry in
                        let canvasFrame = aspectFitFrame(in: geometry.size)
                        ZStack {
                            RoundedRectangle(cornerRadius: 28, style: .continuous)
                                .fill(Color.white.opacity(0.58))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                                        .stroke(Color.white.opacity(0.6), lineWidth: 1)
                                }

                            Image(uiImage: pageImage)
                                .resizable()
                                .scaledToFit()
                                .frame(width: canvasFrame.width, height: canvasFrame.height)
                                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                                .shadow(color: Color.black.opacity(0.08), radius: 18, x: 0, y: 12)

                            overlayPreview(in: canvasFrame)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .frame(maxHeight: 520)
                    .padding(.horizontal, 20)
                    .padding(.top, 2)
                    .padding(.bottom, 12)

                    footer
                }
                .padding(.bottom, max(proxy.safeAreaInsets.bottom, 20))
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                header
                    .padding(.top, 46)
                    .padding(.bottom, 2)
            }
        }
    }

    private var header: some View {
        VStack(spacing: 10) {
            HStack(spacing: 14) {
                Button("Cancel", action: onCancel)
                    .buttonStyle(ScanovaSecondaryButtonStyle())

                Spacer(minLength: 0)

                Button("Apply") {
                    onApply(
                        InsertOverlayPlacement(
                            normalizedCenter: normalizedCenter,
                            normalizedSize: CGSize(width: normalizedWidth, height: normalizedHeight),
                            rotationRadians: rotation
                        )
                    )
                }
                .buttonStyle(ScanovaPrimaryButtonStyle())
            }

            VStack(spacing: 4) {
                Text(title)
                    .font(ScanovaTypography.sectionTitle)
                    .foregroundStyle(ScanovaPalette.ink)
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
            .frame(maxWidth: 320)
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 20)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Button("Reset Position") {
                normalizedCenter = CGPoint(x: 0.5, y: 0.5)
                normalizedWidth = 0.32
                rotation = 0
                dragStartCenter = normalizedCenter
                scaleStartWidth = normalizedWidth
                rotationStart = rotation
            }
            .buttonStyle(ScanovaSecondaryButtonStyle())

            Text("Pinch or drag the corners to resize, and twist to rotate.")
                .font(ScanovaTypography.supporting)
                .foregroundStyle(ScanovaPalette.inkMuted)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 20)
    }

    private func overlayPreview(in canvasFrame: CGRect) -> some View {
        let overlayWidth = canvasFrame.width * normalizedWidth
        let overlayHeight = canvasFrame.height * normalizedHeight
        let center = CGPoint(
            x: canvasFrame.minX + normalizedCenter.x * canvasFrame.width,
            y: canvasFrame.minY + normalizedCenter.y * canvasFrame.height
        )

        return Image(uiImage: overlayImage)
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: overlayWidth, height: overlayHeight)
            .rotationEffect(.radians(rotation))
            .position(center)
            .shadow(color: Color.black.opacity(0.12), radius: 12, x: 0, y: 8)
            .overlay(alignment: .bottomTrailing) {
                Circle()
                    .fill(Color.white)
                    .frame(width: 22, height: 22)
                    .overlay {
                        Circle()
                            .stroke(ScanovaPalette.accent, lineWidth: 2)
                    }
                    .offset(x: 10, y: 10)
            }
            .gesture(dragGesture(in: canvasFrame))
            .simultaneousGesture(magnificationGesture())
            .simultaneousGesture(rotationGesture())
    }

    private func dragGesture(in canvasFrame: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let halfWidth = normalizedWidth / 2
                let halfHeight = normalizedHeight / 2
                let x = dragStartCenter.x + (value.translation.width / max(canvasFrame.width, 1))
                let y = dragStartCenter.y + (value.translation.height / max(canvasFrame.height, 1))
                normalizedCenter = CGPoint(
                    x: min(max(halfWidth, x), 1 - halfWidth),
                    y: min(max(halfHeight, y), 1 - halfHeight)
                )
            }
            .onEnded { _ in
                dragStartCenter = normalizedCenter
            }
    }

    private func magnificationGesture() -> some Gesture {
        MagnificationGesture()
            .onChanged { value in
                normalizedWidth = min(max(0.12, scaleStartWidth * value), 0.82)
            }
            .onEnded { _ in
                scaleStartWidth = normalizedWidth
            }
    }

    private func rotationGesture() -> some Gesture {
        RotationGesture()
            .onChanged { value in
                rotation = rotationStart + CGFloat(value.radians)
            }
            .onEnded { _ in
                rotationStart = rotation
            }
    }

    private func aspectFitFrame(in size: CGSize) -> CGRect {
        let scale = min(size.width / max(pageImage.size.width, 1), size.height / max(pageImage.size.height, 1))
        let fittedSize = CGSize(width: pageImage.size.width * scale, height: pageImage.size.height * scale)
        return CGRect(
            x: (size.width - fittedSize.width) / 2,
            y: (size.height - fittedSize.height) / 2,
            width: fittedSize.width,
            height: fittedSize.height
        )
    }
}

struct StampPickerSheet: View {
    @State private var configuration = InsertStampConfiguration()
    let onCancel: () -> Void
    let onApply: (InsertStampConfiguration) -> Void

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                ScanovaScreenBackground()
                    .ignoresSafeArea()

                VStack(spacing: 18) {
                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 22) {
                            ScanovaCard(accent: configuration.color.color) {
                                Image(uiImage: configuration.makeOverlayImage())
                                    .resizable()
                                    .scaledToFit()
                                    .frame(maxWidth: .infinity, maxHeight: 120)
                            }

                            VStack(alignment: .leading, spacing: 12) {
                                Text("Stamp")
                                    .font(ScanovaTypography.bodyEmphasis)
                                    .foregroundStyle(ScanovaPalette.ink)

                                ForEach(InsertStampKind.allCases) { kind in
                                    Button {
                                        configuration.kind = kind
                                    } label: {
                                        HStack {
                                            Text(kind.title)
                                                .font(ScanovaTypography.body)
                                                .foregroundStyle(ScanovaPalette.ink)
                                            Spacer()
                                            if configuration.kind == kind {
                                                Image(systemName: "checkmark.circle.fill")
                                                    .foregroundStyle(ScanovaPalette.accent)
                                            }
                                        }
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 14)
                                        .background(Color.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }

                            VStack(alignment: .leading, spacing: 12) {
                                Text("Color")
                                    .font(ScanovaTypography.bodyEmphasis)
                                    .foregroundStyle(ScanovaPalette.ink)

                                HStack(spacing: 12) {
                                    ForEach(InsertOverlayColor.allCases) { color in
                                        InsertColorChip(color: color, isSelected: configuration.color == color) {
                                            configuration.color = color
                                        }
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 28)
                    }
                }
                .padding(.bottom, max(proxy.safeAreaInsets.bottom, 20))
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                insertEditorHeader(
                    title: "Insert Stamp",
                    subtitle: "Choose a stamp style and color before placing it on the page.",
                    primaryTitle: "Use",
                    onCancel: onCancel
                ) {
                    onApply(configuration)
                }
                .padding(.top, 8)
                .padding(.bottom, 6)
            }
        }
    }
}

struct ShapePickerSheet: View {
    @State private var configuration = InsertShapeConfiguration()
    let onCancel: () -> Void
    let onApply: (InsertShapeConfiguration) -> Void

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                ScanovaScreenBackground()
                    .ignoresSafeArea()

                VStack(spacing: 18) {
                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 22) {
                            ScanovaCard(accent: configuration.color.color) {
                                Image(uiImage: configuration.makeOverlayImage())
                                    .resizable()
                                    .scaledToFit()
                                    .frame(maxWidth: .infinity, maxHeight: 140)
                            }

                            VStack(alignment: .leading, spacing: 12) {
                                Text("Shape")
                                    .font(ScanovaTypography.bodyEmphasis)
                                    .foregroundStyle(ScanovaPalette.ink)

                                HStack(spacing: 12) {
                                    ForEach(InsertShapeKind.allCases) { kind in
                                        Button {
                                            configuration.kind = kind
                                        } label: {
                                            VStack(spacing: 8) {
                                                Image(systemName: kind.systemImage)
                                                    .font(.system(size: 22, weight: .semibold))
                                                Text(kind.title)
                                                    .font(ScanovaTypography.caption)
                                            }
                                            .foregroundStyle(configuration.kind == kind ? Color.white : ScanovaPalette.ink)
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 14)
                                            .background(
                                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                                    .fill(configuration.kind == kind ? ScanovaPalette.accent : Color.white.opacity(0.9))
                                            )
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }

                            VStack(alignment: .leading, spacing: 12) {
                                Text("Color")
                                    .font(ScanovaTypography.bodyEmphasis)
                                    .foregroundStyle(ScanovaPalette.ink)

                                HStack(spacing: 12) {
                                    ForEach(InsertOverlayColor.allCases) { color in
                                        InsertColorChip(color: color, isSelected: configuration.color == color) {
                                            configuration.color = color
                                        }
                                    }
                                }
                            }

                            VStack(alignment: .leading, spacing: 12) {
                                Text("Stroke")
                                    .font(ScanovaTypography.bodyEmphasis)
                                    .foregroundStyle(ScanovaPalette.ink)

                                HStack(spacing: 10) {
                                    ForEach(InsertStrokeWidth.allCases) { width in
                                        Button {
                                            configuration.strokeWidth = width
                                        } label: {
                                            Text(width.title)
                                                .font(ScanovaTypography.caption)
                                                .foregroundStyle(configuration.strokeWidth == width ? Color.white : ScanovaPalette.ink)
                                                .padding(.horizontal, 14)
                                                .padding(.vertical, 10)
                                                .background(
                                                    Capsule(style: .continuous)
                                                        .fill(configuration.strokeWidth == width ? ScanovaPalette.accent : Color.white.opacity(0.9))
                                                )
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }

                            if configuration.kind != .arrow {
                                Toggle(isOn: $configuration.isFilled) {
                                    Text("Use a soft fill")
                                        .font(ScanovaTypography.body)
                                        .foregroundStyle(ScanovaPalette.ink)
                                }
                                .tint(ScanovaPalette.accent)
                                .padding(18)
                                .background(Color.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 28)
                    }
                }
                .padding(.bottom, max(proxy.safeAreaInsets.bottom, 20))
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                insertEditorHeader(
                    title: "Insert Shapes",
                    subtitle: "Highlight details with a clean circle, rectangle, or arrow.",
                    primaryTitle: "Use",
                    onCancel: onCancel
                ) {
                    onApply(configuration)
                }
                .padding(.top, 8)
                .padding(.bottom, 6)
            }
        }
    }
}

private func insertEditorHeader(
    title: String,
    subtitle: String,
    primaryTitle: String,
    onCancel: @escaping () -> Void,
    onPrimary: @escaping () -> Void
) -> some View {
    VStack(spacing: 10) {
        HStack(spacing: 14) {
            Button("Cancel", action: onCancel)
                .buttonStyle(ScanovaSecondaryButtonStyle())

            Spacer(minLength: 0)

            Button(primaryTitle, action: onPrimary)
                .buttonStyle(ScanovaPrimaryButtonStyle())
        }

        VStack(spacing: 4) {
            Text(title)
                .font(ScanovaTypography.sectionTitle)
                .foregroundStyle(ScanovaPalette.ink)
                .multilineTextAlignment(.center)
                .lineLimit(1)
                .minimumScaleFactor(0.82)

            Text(subtitle)
                .font(ScanovaTypography.supporting)
                .foregroundStyle(ScanovaPalette.inkMuted.opacity(0.96))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: 300)
        .frame(maxWidth: .infinity)
    }
    .padding(.horizontal, 20)
}

private struct InsertColorChip: View {
    let color: InsertOverlayColor
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Circle()
                    .fill(color.color)
                    .frame(width: 34, height: 34)
                    .overlay {
                        Circle()
                            .stroke(Color.white.opacity(0.82), lineWidth: 2)
                    }

                Text(color.title)
                    .font(ScanovaTypography.caption)
                    .foregroundStyle(ScanovaPalette.ink)
            }
            .padding(10)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(isSelected ? ScanovaPalette.accentSoft.opacity(0.82) : Color.white.opacity(0.9))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(isSelected ? ScanovaPalette.accent : Color.white.opacity(0.5), lineWidth: isSelected ? 2 : 1)
            }
        }
        .buttonStyle(.plain)
    }
}

struct SignatureDrawingSheet: View {
    let onCancel: () -> Void
    let onSave: (UIImage) -> Void

    @State private var strokes: [[CGPoint]] = []
    @State private var currentStroke: [CGPoint] = []

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                ScanovaScreenBackground()
                    .ignoresSafeArea()

                VStack(spacing: 18) {
                    GeometryReader { geometry in
                        let canvas = CGRect(origin: .zero, size: geometry.size)
                        ZStack {
                            RoundedRectangle(cornerRadius: 30, style: .continuous)
                                .fill(Color.white.opacity(0.94))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                                        .stroke(Color.white.opacity(0.56), lineWidth: 1)
                                }

                            signaturePath
                                .stroke(style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                                .foregroundStyle(ScanovaPalette.ink)

                            if allPoints.isEmpty {
                                Text("Sign here")
                                    .font(ScanovaTypography.heroTitle)
                                    .foregroundStyle(ScanovaPalette.inkMuted.opacity(0.34))
                            }
                        }
                        .contentShape(Rectangle())
                        .gesture(drawGesture(in: canvas))
                    }
                    .padding(.horizontal, 20)

                    HStack(spacing: 12) {
                        Button("Clear") {
                            strokes.removeAll()
                            currentStroke.removeAll()
                        }
                        .buttonStyle(ScanovaSecondaryButtonStyle())

                        Text("A transparent signature works best on bright pages.")
                            .font(ScanovaTypography.supporting)
                            .foregroundStyle(ScanovaPalette.inkMuted)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, 20)
                }
                .padding(.bottom, max(proxy.safeAreaInsets.bottom, 20))
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                VStack(spacing: 10) {
                    HStack(spacing: 14) {
                        Button("Cancel", action: onCancel)
                            .buttonStyle(ScanovaSecondaryButtonStyle())

                        Spacer(minLength: 0)

                        Button("Use") {
                            onSave(renderSignatureImage())
                        }
                        .buttonStyle(ScanovaPrimaryButtonStyle())
                        .disabled(allPoints.isEmpty)
                    }

                    VStack(spacing: 4) {
                        Text("Draw Signature")
                            .font(ScanovaTypography.sectionTitle)
                            .foregroundStyle(ScanovaPalette.ink)
                            .multilineTextAlignment(.center)
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)

                        Text("Sign once, then place it on the page.")
                            .font(ScanovaTypography.supporting)
                            .foregroundStyle(ScanovaPalette.inkMuted.opacity(0.96))
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: 280)
                    .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 6)
            }
        }
    }

    private var allPoints: [CGPoint] {
        strokes.flatMap { $0 } + currentStroke
    }

    private var signaturePath: Path {
        var path = Path()

        for stroke in strokes + [currentStroke] where !stroke.isEmpty {
            path.addLines(stroke)
        }

        return path
    }

    private func drawGesture(in canvas: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                let point = CGPoint(
                    x: min(max(0, value.location.x), canvas.width),
                    y: min(max(0, value.location.y), canvas.height)
                )

                if value.translation == .zero {
                    currentStroke = [point]
                } else {
                    currentStroke.append(point)
                }
            }
            .onEnded { _ in
                if !currentStroke.isEmpty {
                    strokes.append(currentStroke)
                    currentStroke = []
                }
            }
    }

    private func renderSignatureImage() -> UIImage {
        let targetSize = CGSize(width: 1200, height: 420)
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        let sourceBounds = boundingBox(of: allPoints).insetBy(dx: -18, dy: -18)

        return renderer.image { context in
            let cgContext = context.cgContext
            cgContext.clear(CGRect(origin: .zero, size: targetSize))
            cgContext.setStrokeColor(UIColor(ScanovaPalette.ink).cgColor)
            cgContext.setLineWidth(18)
            cgContext.setLineCap(.round)
            cgContext.setLineJoin(.round)

            let scale = min(
                (targetSize.width - 120) / max(sourceBounds.width, 1),
                (targetSize.height - 120) / max(sourceBounds.height, 1)
            )

            cgContext.translateBy(x: 60, y: 60)
            cgContext.scaleBy(x: scale, y: scale)
            cgContext.translateBy(x: -sourceBounds.minX, y: -sourceBounds.minY)

            for stroke in strokes where !stroke.isEmpty {
                cgContext.beginPath()
                cgContext.move(to: stroke[0])
                for point in stroke.dropFirst() {
                    cgContext.addLine(to: point)
                }
                cgContext.strokePath()
            }
        }
    }

    private func boundingBox(of points: [CGPoint]) -> CGRect {
        guard let first = points.first else { return CGRect(x: 0, y: 0, width: 1, height: 1) }
        return points.dropFirst().reduce(CGRect(origin: first, size: .zero)) { partial, point in
            partial.union(CGRect(origin: point, size: .zero))
        }
    }
}
