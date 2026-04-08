import Foundation
import UIKit
import Vision

struct OCRResult {
    let fullText: String
    let pageText: [Int: String]
}

struct OCRService {
    func recognizeText(in images: [UIImage]) async -> OCRResult {
        var pageText: [Int: String] = [:]

        for (index, image) in images.enumerated() {
            let text = await recognizeText(in: image)
            pageText[index] = text
        }

        let fullText = pageText
            .sorted(by: { $0.key < $1.key })
            .map(\.value)
            .joined(separator: "\n\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return OCRResult(fullText: fullText, pageText: pageText)
    }

    private func recognizeText(in image: UIImage) async -> String {
        await withCheckedContinuation { continuation in
            guard let cgImage = image.cgImage else {
                continuation.resume(returning: "")
                return
            }

            let request = VNRecognizeTextRequest { request, _ in
                let text = (request.results as? [VNRecognizedTextObservation])?
                    .compactMap { $0.topCandidates(1).first?.string }
                    .joined(separator: "\n") ?? ""

                continuation.resume(returning: text)
            }

            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true

            Task.detached(priority: .userInitiated) {
                let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
                do {
                    try handler.perform([request])
                } catch {
                    continuation.resume(returning: "")
                }
            }
        }
    }
}
