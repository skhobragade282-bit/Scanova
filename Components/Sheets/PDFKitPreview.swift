import PDFKit
import SwiftUI
import UIKit

struct PDFKitPreview: UIViewRepresentable {
    let data: Data
    var fitSinglePage = false
    var selectionEnabled = false
    var selectedPageIndexes: Set<Int> = []
    var onPageTap: ((Int) -> Void)? = nil
    var onVisiblePageChanged: ((Int) -> Void)? = nil
    var resetZoomToken: String? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> OverlayAwarePDFView {
        let view = OverlayAwarePDFView()
        view.autoScales = true
        view.displayMode = fitSinglePage ? .singlePage : .singlePageContinuous
        view.displayDirection = fitSinglePage ? .horizontal : .vertical
        view.displaysPageBreaks = false
        view.pageShadowsEnabled = false
        view.backgroundColor = .clear
        view.onLayoutChanged = { [weak coordinator = context.coordinator] in
            coordinator?.refreshSelectionOverlays()
        }

        let tapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        tapGesture.cancelsTouchesInView = false
        view.addGestureRecognizer(tapGesture)

        context.coordinator.pdfView = view
        context.coordinator.startObservingPageChanges(for: view)
        return view
    }

    func updateUIView(_ uiView: OverlayAwarePDFView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.pdfView = uiView
        uiView.displayMode = fitSinglePage ? .singlePage : .singlePageContinuous
        uiView.displayDirection = fitSinglePage ? .horizontal : .vertical

        let documentChanged = context.coordinator.lastDocumentData != data
        let zoomResetChanged = context.coordinator.lastResetZoomToken != resetZoomToken

        if documentChanged {
            uiView.document = PDFDocument(data: data)
            context.coordinator.lastDocumentData = data
        }

        if documentChanged || zoomResetChanged {
            context.coordinator.lastResetZoomToken = resetZoomToken
            resetToFit(uiView)
        }

        DispatchQueue.main.async {
            context.coordinator.refreshSelectionOverlays()
        }
    }

    private func resetToFit(_ pdfView: PDFView) {
        if let firstPage = pdfView.document?.page(at: 0) {
            pdfView.go(to: firstPage)
        }
        pdfView.scaleFactor = pdfView.scaleFactorForSizeToFit
        pdfView.autoScales = true
    }

    final class Coordinator: NSObject {
        var parent: PDFKitPreview
        weak var pdfView: OverlayAwarePDFView?
        var lastDocumentData: Data?
        var lastResetZoomToken: String?
        private var overlayViews: [Int: PDFPageSelectionOverlayView] = [:]
        private var pageChangeObserver: NSObjectProtocol?

        init(parent: PDFKitPreview) {
            self.parent = parent
        }

        deinit {
            if let pageChangeObserver {
                NotificationCenter.default.removeObserver(pageChangeObserver)
            }
        }

        func startObservingPageChanges(for pdfView: PDFView) {
            if let pageChangeObserver {
                NotificationCenter.default.removeObserver(pageChangeObserver)
            }

            pageChangeObserver = NotificationCenter.default.addObserver(
                forName: Notification.Name.PDFViewPageChanged,
                object: pdfView,
                queue: .main
            ) { [weak self, weak pdfView] _ in
                guard let self, let pdfView, let document = pdfView.document, let currentPage = pdfView.currentPage else { return }
                let index = document.index(for: currentPage)
                guard index != NSNotFound else { return }
                self.parent.onVisiblePageChanged?(index)
            }
        }

        @objc
        func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let pdfView,
                  let document = pdfView.document else { return }

            guard parent.onPageTap != nil else { return }

            let location = gesture.location(in: pdfView)
            guard let page = pdfView.page(for: location, nearest: true) else { return }

            let index = document.index(for: page)
            guard index != NSNotFound else { return }
            parent.onPageTap?(index)
        }

        func refreshSelectionOverlays() {
            guard let pdfView,
                  let document = pdfView.document,
                  let documentView = pdfView.documentView else {
                clearOverlays()
                return
            }

            guard parent.selectionEnabled, !parent.selectedPageIndexes.isEmpty else {
                clearOverlays()
                return
            }

            var activeIndexes = Set<Int>()

            for index in parent.selectedPageIndexes.sorted() {
                guard let page = document.page(at: index) else { continue }

                let pageFrame = pdfView.convert(page.bounds(for: .mediaBox), from: page).integral
                guard pageFrame.intersects(pdfView.bounds) else {
                    overlayViews[index]?.removeFromSuperview()
                    overlayViews[index] = nil
                    continue
                }

                let insetFrame = pageFrame.insetBy(dx: 6, dy: 6)
                let overlay = overlayViews[index] ?? PDFPageSelectionOverlayView(pageNumber: index + 1)
                overlay.update(pageNumber: index + 1)
                overlay.frame = insetFrame

                if overlay.superview !== documentView {
                    documentView.addSubview(overlay)
                }

                activeIndexes.insert(index)
                overlayViews[index] = overlay
            }

            for (index, overlay) in overlayViews where !activeIndexes.contains(index) {
                overlay.removeFromSuperview()
                overlayViews[index] = nil
            }
        }

        private func clearOverlays() {
            for overlay in overlayViews.values {
                overlay.removeFromSuperview()
            }
            overlayViews.removeAll()
        }
    }
}

final class OverlayAwarePDFView: PDFView {
    var onLayoutChanged: (() -> Void)?

    override func layoutSubviews() {
        super.layoutSubviews()
        onLayoutChanged?()
    }
}

final class PDFPageSelectionOverlayView: UIView {
    private let badgeLabel = UILabel()

    init(pageNumber: Int) {
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        layer.cornerRadius = 22
        layer.cornerCurve = .continuous
        layer.borderWidth = 3
        layer.borderColor = UIColor(ScanovaPalette.accent).cgColor
        backgroundColor = UIColor(ScanovaPalette.accentSoft.opacity(0.18))

        let badgeBackground = UIView()
        badgeBackground.translatesAutoresizingMaskIntoConstraints = false
        badgeBackground.backgroundColor = UIColor(ScanovaPalette.accent)
        badgeBackground.layer.cornerRadius = 16
        badgeBackground.layer.cornerCurve = .continuous

        badgeLabel.translatesAutoresizingMaskIntoConstraints = false
        badgeLabel.font = UIFont.systemFont(ofSize: 13, weight: .bold)
        badgeLabel.textColor = .white
        badgeLabel.textAlignment = .center
        badgeLabel.text = "\(pageNumber)"

        addSubview(badgeBackground)
        badgeBackground.addSubview(badgeLabel)

        NSLayoutConstraint.activate([
            badgeBackground.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            badgeBackground.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            badgeBackground.widthAnchor.constraint(greaterThanOrEqualToConstant: 32),
            badgeBackground.heightAnchor.constraint(equalToConstant: 32),

            badgeLabel.leadingAnchor.constraint(equalTo: badgeBackground.leadingAnchor, constant: 9),
            badgeLabel.trailingAnchor.constraint(equalTo: badgeBackground.trailingAnchor, constant: -9),
            badgeLabel.centerYAnchor.constraint(equalTo: badgeBackground.centerYAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(pageNumber: Int) {
        badgeLabel.text = "\(pageNumber)"
    }
}
