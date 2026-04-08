import SwiftUI
import UIKit

struct CropImageSheet: View {
    let image: UIImage
    let title: String
    let onApply: (UIImage) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var normalizedCropRect = CGRect(x: 0.1, y: 0.1, width: 0.8, height: 0.8)
    @State private var interactionStartRect: CGRect?

    private let minimumCropLength: CGFloat = 80

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                let canvasRect = cropCanvasRect(for: geometry.size)
                let imageRect = fittedImageRect(for: image.size, inside: canvasRect)
                let cropRect = denormalizedCropRect(in: imageRect)

                VStack(spacing: 20) {
                    Spacer(minLength: 0)

                    ZStack {
                        Color.black.opacity(0.94)

                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(width: imageRect.width, height: imageRect.height)
                            .position(x: imageRect.midX, y: imageRect.midY)

                        CropShadeOverlay(imageRect: imageRect, cropRect: cropRect)
                            .allowsHitTesting(false)

                        CropBox(cropRect: cropRect)
                            .gesture(moveGesture(imageRect: imageRect))

                        ForEach(CropHandle.allCases, id: \.self) { handle in
                            CropHandleView(position: cropRectPoint(for: handle, in: cropRect))
                                .gesture(resizeGesture(for: handle, imageRect: imageRect))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: canvasRect.height)
                    .clipShape(RoundedRectangle(cornerRadius: 28))
                    .padding(.horizontal, 16)

                    VStack(spacing: 10) {
                        Text("Drag inside the crop box to reposition it. Drag the corners to set the exact crop.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)

                        Button("Reset Crop") {
                            normalizedCropRect = CGRect(x: 0.1, y: 0.1, width: 0.8, height: 0.8)
                        }
                        .buttonStyle(.bordered)
                    }

                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Cancel") {
                            dismiss()
                        }
                    }

                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Apply") {
                            onApply(cropImage())
                            dismiss()
                        }
                    }
                }
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
            }
            .ignoresSafeArea()
        }
    }

    private func cropCanvasRect(for containerSize: CGSize) -> CGRect {
        let horizontalInset: CGFloat = 16
        let availableWidth = max(240, containerSize.width - (horizontalInset * 2))
        let availableHeight = max(280, containerSize.height - 220)
        return CGRect(x: 0, y: 0, width: availableWidth, height: availableHeight)
    }

    private func fittedImageRect(for imageSize: CGSize, inside canvasRect: CGRect) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else {
            return canvasRect
        }

        let scale = min(canvasRect.width / imageSize.width, canvasRect.height / imageSize.height)
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)

        return CGRect(
            x: (canvasRect.width - size.width) / 2,
            y: (canvasRect.height - size.height) / 2,
            width: size.width,
            height: size.height
        )
    }

    private func denormalizedCropRect(in imageRect: CGRect) -> CGRect {
        CGRect(
            x: imageRect.minX + normalizedCropRect.minX * imageRect.width,
            y: imageRect.minY + normalizedCropRect.minY * imageRect.height,
            width: normalizedCropRect.width * imageRect.width,
            height: normalizedCropRect.height * imageRect.height
        )
    }

    private func moveGesture(imageRect: CGRect) -> some Gesture {
        DragGesture()
            .onChanged { value in
                if interactionStartRect == nil {
                    interactionStartRect = normalizedCropRect
                }

                guard let startRect = interactionStartRect else { return }
                let deltaX = value.translation.width / imageRect.width
                let deltaY = value.translation.height / imageRect.height
                var nextRect = startRect
                nextRect.origin.x += deltaX
                nextRect.origin.y += deltaY
                normalizedCropRect = clamped(nextRect, in: imageRect)
            }
            .onEnded { _ in
                interactionStartRect = nil
            }
    }

    private func resizeGesture(for handle: CropHandle, imageRect: CGRect) -> some Gesture {
        DragGesture()
            .onChanged { value in
                if interactionStartRect == nil {
                    interactionStartRect = normalizedCropRect
                }

                guard let startRect = interactionStartRect else { return }
                let dx = value.translation.width / imageRect.width
                let dy = value.translation.height / imageRect.height
                normalizedCropRect = clamped(rectByResizing(startRect, handle: handle, dx: dx, dy: dy), in: imageRect)
            }
            .onEnded { _ in
                interactionStartRect = nil
            }
    }

    private func rectByResizing(_ rect: CGRect, handle: CropHandle, dx: CGFloat, dy: CGFloat) -> CGRect {
        var nextRect = rect

        switch handle {
        case .topLeading:
            nextRect.origin.x += dx
            nextRect.origin.y += dy
            nextRect.size.width -= dx
            nextRect.size.height -= dy
        case .topTrailing:
            nextRect.origin.y += dy
            nextRect.size.width += dx
            nextRect.size.height -= dy
        case .bottomLeading:
            nextRect.origin.x += dx
            nextRect.size.width -= dx
            nextRect.size.height += dy
        case .bottomTrailing:
            nextRect.size.width += dx
            nextRect.size.height += dy
        }

        return nextRect
    }

    private func clamped(_ rect: CGRect, in imageRect: CGRect) -> CGRect {
        let minimumWidth = minimumCropLength / max(imageRect.width, 1)
        let minimumHeight = minimumCropLength / max(imageRect.height, 1)

        var nextRect = rect.standardized
        nextRect.size.width = max(minimumWidth, min(nextRect.width, 1))
        nextRect.size.height = max(minimumHeight, min(nextRect.height, 1))
        nextRect.origin.x = min(max(0, nextRect.origin.x), 1 - nextRect.width)
        nextRect.origin.y = min(max(0, nextRect.origin.y), 1 - nextRect.height)
        return nextRect
    }

    private func cropRectPoint(for handle: CropHandle, in cropRect: CGRect) -> CGPoint {
        switch handle {
        case .topLeading:
            return CGPoint(x: cropRect.minX, y: cropRect.minY)
        case .topTrailing:
            return CGPoint(x: cropRect.maxX, y: cropRect.minY)
        case .bottomLeading:
            return CGPoint(x: cropRect.minX, y: cropRect.maxY)
        case .bottomTrailing:
            return CGPoint(x: cropRect.maxX, y: cropRect.maxY)
        }
    }

    private func cropImage() -> UIImage {
        let source = image.normalizedForCropping()
        guard let cgImage = source.cgImage else { return image }

        let cropRect = CGRect(
            x: normalizedCropRect.minX * CGFloat(cgImage.width),
            y: normalizedCropRect.minY * CGFloat(cgImage.height),
            width: normalizedCropRect.width * CGFloat(cgImage.width),
            height: normalizedCropRect.height * CGFloat(cgImage.height)
        ).integral

        guard cropRect.width > 1,
              cropRect.height > 1,
              let croppedImage = cgImage.cropping(to: cropRect) else {
            return source
        }

        return UIImage(cgImage: croppedImage, scale: source.scale, orientation: .up)
    }
}

private enum CropHandle: CaseIterable {
    case topLeading
    case topTrailing
    case bottomLeading
    case bottomTrailing
}

private struct CropShadeOverlay: View {
    let imageRect: CGRect
    let cropRect: CGRect

    var body: some View {
        GeometryReader { proxy in
            Path { path in
                path.addRect(CGRect(origin: .zero, size: proxy.size))
                path.addRoundedRect(in: cropRect, cornerSize: CGSize(width: 20, height: 20))
            }
            .fill(style: FillStyle(eoFill: true))
            .foregroundStyle(.black.opacity(0.5))

            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.white, lineWidth: 2)
                .frame(width: cropRect.width, height: cropRect.height)
                .position(x: cropRect.midX, y: cropRect.midY)

            RoundedRectangle(cornerRadius: 28)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
                .frame(width: imageRect.width, height: imageRect.height)
                .position(x: imageRect.midX, y: imageRect.midY)
        }
    }
}

private struct CropBox: View {
    let cropRect: CGRect

    var body: some View {
        RoundedRectangle(cornerRadius: 20)
            .fill(Color.clear)
            .frame(width: cropRect.width, height: cropRect.height)
            .contentShape(RoundedRectangle(cornerRadius: 20))
            .position(x: cropRect.midX, y: cropRect.midY)
    }
}

private struct CropHandleView: View {
    let position: CGPoint

    var body: some View {
        Circle()
            .fill(.white)
            .frame(width: 24, height: 24)
            .overlay {
                Circle()
                    .stroke(Color.black.opacity(0.2), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.18), radius: 8, x: 0, y: 2)
            .position(position)
    }
}

private extension UIImage {
    func normalizedForCropping() -> UIImage {
        guard imageOrientation != .up else { return self }

        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
