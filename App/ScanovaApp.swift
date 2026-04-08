import SwiftUI

@main
struct ScanovaApp: App {
    @StateObject private var router = AppRouter()
    @StateObject private var workflowController = WorkflowController()
    @StateObject private var subscriptionService = SubscriptionService()
    @StateObject private var accountService = AccountService()
    @StateObject private var appPreferences = AppPreferences()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(router)
                .environmentObject(workflowController)
                .environmentObject(subscriptionService)
                .environmentObject(accountService)
                .environmentObject(appPreferences)
                .task {
                    workflowController.setAutoNamingEnabled(appPreferences.autoNamingEnabled)
                    await subscriptionService.prepareStore()
                }
                .onChange(of: appPreferences.autoNamingEnabled) { _, enabled in
                    workflowController.setAutoNamingEnabled(enabled)
                }
        }
    }
}
