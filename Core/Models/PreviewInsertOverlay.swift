import SwiftUI
import UIKit

struct PreviewInsertDraft: Identifiable {
    let id = UUID()
    let tool: SubscriptionService.PremiumFeature
    let title: String
    let overlayImage: UIImage
}

struct InsertOverlayPlacement {
    var normalizedCenter: CGPoint
    var normalizedSize: CGSize
    var rotationRadians: CGFloat

    static let centered = InsertOverlayPlacement(
        normalizedCenter: CGPoint(x: 0.5, y: 0.5),
        normalizedSize: CGSize(width: 0.34, height: 0.20),
        rotationRadians: 0
    )
}

enum InsertOverlayColor: String, CaseIterable, Identifiable {
    case red
    case blue
    case green
    case gray

    var id: String { rawValue }

    var title: String {
        rawValue.capitalized
    }

    var color: Color {
        switch self {
        case .red:
            return Color(red: 0.82, green: 0.17, blue: 0.20)
        case .blue:
            return ScanovaPalette.accent
        case .green:
            return Color(red: 0.15, green: 0.55, blue: 0.34)
        case .gray:
            return Color(red: 0.40, green: 0.43, blue: 0.48)
        }
    }

    var uiColor: UIColor {
        UIColor(color)
    }
}

enum InsertStampKind: String, CaseIterable, Identifiable {
    case approved
    case paid
    case received
    case confidential

    var id: String { rawValue }

    var title: String {
        rawValue.capitalized
    }

    var badgeText: String {
        switch self {
        case .approved:
            return "APPROVED"
        case .paid:
            return "PAID"
        case .received:
            return "RECEIVED"
        case .confidential:
            return "CONFIDENTIAL"
        }
    }
}

enum InsertShapeKind: String, CaseIterable, Identifiable {
    case rectangle
    case circle
    case arrow

    var id: String { rawValue }

    var title: String {
        switch self {
        case .rectangle:
            return "Rectangle"
        case .circle:
            return "Circle"
        case .arrow:
            return "Arrow"
        }
    }

    var systemImage: String {
        switch self {
        case .rectangle:
            return "rectangle"
        case .circle:
            return "circle"
        case .arrow:
            return "arrow.up.right"
        }
    }
}

enum InsertStrokeWidth: CGFloat, CaseIterable, Identifiable {
    case light = 8
    case medium = 14
    case bold = 22

    var id: CGFloat { rawValue }

    var title: String {
        switch self {
        case .light:
            return "Light"
        case .medium:
            return "Medium"
        case .bold:
            return "Bold"
        }
    }
}

struct InsertStampConfiguration {
    var kind: InsertStampKind = .approved
    var color: InsertOverlayColor = .red

    func makeOverlayImage() -> UIImage {
        let size = CGSize(width: 1200, height: 420)
        let renderer = UIGraphicsImageRenderer(size: size)

        return renderer.image { context in
            let cgContext = context.cgContext
            cgContext.clear(CGRect(origin: .zero, size: size))
            cgContext.translateBy(x: size.width / 2, y: size.height / 2)
            cgContext.rotate(by: -.pi / 18)
            cgContext.translateBy(x: -size.width / 2, y: -size.height / 2)

            let borderRect = CGRect(x: 88, y: 88, width: size.width - 176, height: size.height - 176)
            cgContext.setStrokeColor(color.uiColor.withAlphaComponent(0.95).cgColor)
            cgContext.setLineWidth(30)
            cgContext.stroke(borderRect)

            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center

            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 140, weight: .black),
                .foregroundColor: color.uiColor.withAlphaComponent(0.95),
                .paragraphStyle: paragraph,
                .kern: 6
            ]

            let text = NSAttributedString(string: kind.badgeText, attributes: attributes)
            text.draw(in: CGRect(x: 110, y: 110, width: size.width - 220, height: size.height - 220))
        }
    }
}

struct InsertShapeConfiguration {
    var kind: InsertShapeKind = .rectangle
    var color: InsertOverlayColor = .blue
    var strokeWidth: InsertStrokeWidth = .medium
    var isFilled = false

    func makeOverlayImage() -> UIImage {
        let size: CGSize
        switch kind {
        case .arrow:
            size = CGSize(width: 1200, height: 500)
        case .rectangle, .circle:
            size = CGSize(width: 900, height: 700)
        }

        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            let cgContext = context.cgContext
            cgContext.clear(CGRect(origin: .zero, size: size))
            cgContext.setLineJoin(.round)
            cgContext.setLineCap(.round)
            cgContext.setStrokeColor(color.uiColor.cgColor)
            cgContext.setLineWidth(strokeWidth.rawValue)

            switch kind {
            case .rectangle:
                let rect = CGRect(x: 90, y: 90, width: size.width - 180, height: size.height - 180)
                if isFilled {
                    cgContext.setFillColor(color.uiColor.withAlphaComponent(0.18).cgColor)
                    cgContext.fill(rect)
                }
                cgContext.stroke(rect)
            case .circle:
                let rect = CGRect(x: 90, y: 90, width: size.width - 180, height: size.height - 180)
                if isFilled {
                    cgContext.setFillColor(color.uiColor.withAlphaComponent(0.18).cgColor)
                    cgContext.fillEllipse(in: rect)
                }
                cgContext.strokeEllipse(in: rect)
            case .arrow:
                let start = CGPoint(x: 120, y: size.height - 120)
                let end = CGPoint(x: size.width - 170, y: 140)
                cgContext.move(to: start)
                cgContext.addLine(to: end)
                cgContext.strokePath()

                let angle = atan2(end.y - start.y, end.x - start.x)
                let headLength: CGFloat = 110
                let left = CGPoint(
                    x: end.x - headLength * cos(angle - .pi / 7),
                    y: end.y - headLength * sin(angle - .pi / 7)
                )
                let right = CGPoint(
                    x: end.x - headLength * cos(angle + .pi / 7),
                    y: end.y - headLength * sin(angle + .pi / 7)
                )
                cgContext.move(to: end)
                cgContext.addLine(to: left)
                cgContext.move(to: end)
                cgContext.addLine(to: right)
                cgContext.strokePath()
            }
        }
    }
}

enum RecentSignatureStore {
    private static let key = "scanova.preview.recentSignature"

    static func load() -> UIImage? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return UIImage(data: data)
    }

    static func save(_ image: UIImage) {
        guard let data = image.pngData() else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
