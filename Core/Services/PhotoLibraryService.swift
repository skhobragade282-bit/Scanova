import Photos
import UIKit

struct PhotoLibraryService {
    func save(images: [UIImage]) async throws {
        guard !images.isEmpty else { return }

        let authorizationStatus = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard authorizationStatus == .authorized || authorizationStatus == .limited else {
            throw PhotoLibraryError.permissionDenied
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges({
                for image in images {
                    PHAssetChangeRequest.creationRequestForAsset(from: image)
                }
            }) { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: PhotoLibraryError.saveFailed)
                }
            }
        }
    }
}

enum PhotoLibraryError: LocalizedError {
    case permissionDenied
    case saveFailed

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Allow Photos access to save images."
        case .saveFailed:
            return "Could not save the images to Photos."
        }
    }
}
