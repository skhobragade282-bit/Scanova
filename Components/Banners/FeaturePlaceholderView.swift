import SwiftUI

struct FeaturePlaceholderView: View {
    let title: String
    let description: String
    let primaryActionTitle: String
    let secondaryActionTitle: String?
    let primaryAction: () -> Void
    var secondaryAction: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            VStack(spacing: 12) {
                Text(title)
                    .font(.title.weight(.semibold))

                Text(description)
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 12) {
                Button(primaryActionTitle, action: primaryAction)
                    .buttonStyle(.borderedProminent)

                if let secondaryActionTitle, let secondaryAction {
                    Button(secondaryActionTitle, action: secondaryAction)
                        .buttonStyle(.bordered)
                }
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }
}
