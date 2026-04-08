import SwiftUI

struct ZoomableImageSheet: View {
    let image: UIImage
    let title: String

    @Environment(\.dismiss) private var dismiss
    @State private var zoomScale: CGFloat = 1
    @State private var accumulatedZoomScale: CGFloat = 1

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                ScrollView([.horizontal, .vertical], showsIndicators: false) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .scaleEffect(zoomScale)
                        .frame(
                            width: max(geometry.size.width, geometry.size.width * zoomScale),
                            height: max(geometry.size.height, geometry.size.height * zoomScale)
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .gesture(
                            MagnificationGesture()
                                .onChanged { value in
                                    zoomScale = max(1, min(5, accumulatedZoomScale * value))
                                }
                                .onEnded { _ in
                                    accumulatedZoomScale = zoomScale
                                }
                        )
                        .onTapGesture(count: 2) {
                            zoomScale = 1
                            accumulatedZoomScale = 1
                        }
                }
                .background(Color.black.opacity(0.96))
            }
            .ignoresSafeArea()
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
