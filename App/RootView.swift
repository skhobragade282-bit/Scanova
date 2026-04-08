import SwiftUI

struct RootView: View {
    @EnvironmentObject private var router: AppRouter

    var body: some View {
        NavigationStack {
            Group {
                switch router.rootDestination {
                case .workflow:
                    WorkflowContainerView()
                case .paywall:
                    PaywallView()
                }
            }
            .background(ScanovaPalette.background.ignoresSafeArea())
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(router.rootDestination == .workflow ? .inline : .large)
            .toolbar(router.rootDestination == .workflow ? .hidden : .visible, for: .navigationBar)
        }
    }

    private var navigationTitle: String {
        switch router.rootDestination {
        case .workflow:
            return ""
        case .paywall:
            return "Scanova Pro"
        }
    }
}

private struct WorkflowContainerView: View {
    @EnvironmentObject private var workflowController: WorkflowController

    var body: some View {
        switch workflowController.currentStep {
        case .launch:
            LaunchView()
        case .capture:
            CaptureView()
        case .export:
            ExportView()
        case .viewer:
            ViewerView()
        case .recent:
            RecentView()
        case .selection:
            ViewerView()
        }
    }
}
