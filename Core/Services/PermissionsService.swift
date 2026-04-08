import Foundation

struct PermissionsService {
    enum PermissionStatus {
        case notDetermined
        case granted
        case denied
    }

    func cameraStatus() -> PermissionStatus {
        .notDetermined
    }

    func photoLibraryStatus() -> PermissionStatus {
        .notDetermined
    }
}
