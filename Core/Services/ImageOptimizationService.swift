import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit

struct ImageOptimizationService {
    private let context = CIContext(options: nil)

    func optimize(pages: [DocumentPage], for type: DocumentType) -> ([DocumentPage], EnhancementProfile) {
        let profile = profile(for: type)
        guard profile != .none else { return (pages, .none) }

        let optimizedPages = pages.map { page in
            var updatedPage = page
            updatedPage.image = optimizedImage(for: page.image, profile: profile) ?? page.image
            return updatedPage
        }

        return (optimizedPages, profile)
    }

    private func profile(for type: DocumentType) -> EnhancementProfile {
        switch type {
        case .notes:
            return .notes
        case .invoice:
            return .invoice
        case .receipt:
            return .receipt
        case .general:
            return .document
        }
    }

    private func optimizedImage(for image: UIImage, profile: EnhancementProfile) -> UIImage? {
        guard let inputImage = CIImage(image: image) else { return nil }

        let colorControls = CIFilter.colorControls()
        colorControls.inputImage = inputImage

        switch profile {
        case .notes:
            colorControls.saturation = 0.05
            colorControls.contrast = 1.18
            colorControls.brightness = 0.02
        case .receipt:
            colorControls.saturation = 0.02
            colorControls.contrast = 1.14
            colorControls.brightness = 0.02
        case .invoice:
            colorControls.saturation = 0.9
            colorControls.contrast = 1.08
            colorControls.brightness = 0.015
        case .document:
            // Keep "auto color" subtle: preserve natural color and only clean up tone.
            colorControls.saturation = 1.05
            colorControls.contrast = 1.06
            colorControls.brightness = 0.01
        case .none:
            return image
        }

        guard let adjusted = colorControls.outputImage else { return nil }

        let sharpen = CIFilter.sharpenLuminance()
        sharpen.inputImage = adjusted
        sharpen.sharpness = profile == .notes || profile == .receipt ? 0.28 : 0.18

        guard let output = sharpen.outputImage,
              let cgImage = context.createCGImage(output, from: output.extent) else {
            return nil
        }

        return UIImage(cgImage: cgImage, scale: image.scale, orientation: image.imageOrientation)
    }
}
