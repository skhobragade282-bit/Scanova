import Combine
import Foundation

final class AppRouter: ObservableObject {
    enum RootDestination: String {
        case workflow
        case paywall
    }

    @Published var rootDestination: RootDestination = .workflow

    func showWorkflow() {
        rootDestination = .workflow
    }

    func showPaywall() {
        rootDestination = .paywall
    }
}
