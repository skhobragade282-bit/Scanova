import Foundation
import UIKit

struct DocumentPage: Identifiable {
    let id: UUID
    var image: UIImage
    var originalImage: UIImage?
    var source: ImportSource
    var sourcePageIndex: Int?

    init(
        id: UUID = UUID(),
        image: UIImage,
        originalImage: UIImage? = nil,
        source: ImportSource,
        sourcePageIndex: Int? = nil
    ) {
        self.id = id
        self.image = image
        self.originalImage = originalImage
        self.source = source
        self.sourcePageIndex = sourcePageIndex
    }
}
