import SwiftUI
import UIKit
import VisionKit
import PhotosUI

struct DocumentCameraSheet: UIViewControllerRepresentable {
    let onScan: ([UIImage]) -> Void
    let onCancel: () -> Void
    let onError: (Error) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onScan: onScan, onCancel: onCancel, onError: onError)
    }

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: VNDocumentCameraViewController, context: Context) {
    }
}

final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
    private let onScan: ([UIImage]) -> Void
    private let onCancel: () -> Void
    private let onError: (Error) -> Void

    init(
        onScan: @escaping ([UIImage]) -> Void,
        onCancel: @escaping () -> Void,
        onError: @escaping (Error) -> Void
    ) {
        self.onScan = onScan
        self.onCancel = onCancel
        self.onError = onError
    }

    func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
        onCancel()
    }

    func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
        onError(error)
    }

    func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
        let images = (0..<scan.pageCount).map { scan.imageOfPage(at: $0) }
        onScan(images)
    }
}

struct SignaturePhotoPickerSheet: UIViewControllerRepresentable {
    let onSelect: (UIImage) -> Void
    let onCancel: () -> Void
    let onError: () -> Void

    func makeCoordinator() -> SignatureCoordinator {
        SignatureCoordinator(onSelect: onSelect, onCancel: onCancel, onError: onError)
    }

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration(photoLibrary: .shared())
        configuration.filter = .images
        configuration.selectionLimit = 1

        let controller = PHPickerViewController(configuration: configuration)
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {
    }
}

final class SignatureCoordinator: NSObject, PHPickerViewControllerDelegate {
    private let onSelect: (UIImage) -> Void
    private let onCancel: () -> Void
    private let onError: () -> Void

    init(
        onSelect: @escaping (UIImage) -> Void,
        onCancel: @escaping () -> Void,
        onError: @escaping () -> Void
    ) {
        self.onSelect = onSelect
        self.onCancel = onCancel
        self.onError = onError
    }

    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        guard let itemProvider = results.first?.itemProvider else {
            onCancel()
            return
        }

        if itemProvider.canLoadObject(ofClass: UIImage.self) {
            itemProvider.loadObject(ofClass: UIImage.self) { object, _ in
                DispatchQueue.main.async {
                    if let image = object as? UIImage {
                        self.onSelect(image)
                    } else {
                        self.onError()
                    }
                }
            }
        } else {
            DispatchQueue.main.async {
                self.onError()
            }
        }
    }
}
