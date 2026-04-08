import SwiftUI

struct LaunchView: View {
    @EnvironmentObject private var workflowController: WorkflowController

    var body: some View {
        VStack(spacing: 16) {
            Text("Scanova")
                .font(.largeTitle.weight(.bold))

            Text("Smart scanning, conversion, and document understanding.")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
        .task {
            guard workflowController.currentStep == .launch else { return }
            workflowController.goToNextStep()
        }
    }
}
