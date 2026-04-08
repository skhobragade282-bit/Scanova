import SwiftUI

struct PaywallView: View {
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var subscriptionService: SubscriptionService
    @State private var selectedProductID: String?
    @State private var presentedDetailSheet: ScanovaSupportDetail?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                topBar
                heroCard
                if subscriptionService.isSubscribed {
                    activeAccessCard
                } else {
                    planChooser
                }
                footerActions
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 140)
        }
        .background {
            ScanovaScreenBackground()
        }
        .toolbar(.hidden, for: .navigationBar)
        .task {
            await subscriptionService.prepareStore()
            syncSelectionWithProducts()
        }
        .onChange(of: subscriptionService.productDisplays.map(\.id)) { _, _ in
            syncSelectionWithProducts()
        }
        .sheet(item: $presentedDetailSheet) { detailSheet in
            ScanovaSupportDetailSheet(detail: detailSheet)
        }
        .scanovaBackSwipe(isEnabled: presentedDetailSheet == nil) {
            router.showWorkflow()
        }
    }

    private var topBar: some View {
        HStack(alignment: .center, spacing: 12) {
            Button {
                router.showWorkflow()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(ScanovaPalette.ink)
                    .frame(width: 36, height: 36)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay {
                        Circle()
                            .stroke(Color.white.opacity(0.72), lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)

            Text("Scanova Pro")
                .font(ScanovaTypography.screenTitle)
                .foregroundStyle(ScanovaPalette.ink)

            Spacer(minLength: 12)
        }
    }

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                premiumEyebrow
                Spacer(minLength: 12)
                premiumOrb
            }

            Text(paywallHeadline)
                .font(ScanovaTypography.heroTitle)
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)

            Text(paywallSupportText)
                .font(ScanovaTypography.supporting)
                .foregroundStyle(.white.opacity(0.84))
                .fixedSize(horizontal: false, vertical: true)

            heroHighlights

            if !subscriptionService.isSubscribed, let plan = selectedPlan {
                heroOfferStrip(for: plan)
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 34, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.10, green: 0.13, blue: 0.24),
                                ScanovaPalette.accentDark,
                                Color(red: 0.08, green: 0.10, blue: 0.16)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                Circle()
                    .fill(ScanovaPalette.accent.opacity(0.26))
                    .frame(width: 220, height: 220)
                    .blur(radius: 18)
                    .offset(x: 110, y: -64)

                RoundedRectangle(cornerRadius: 34, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.10), Color.clear],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .stroke(Color.white.opacity(0.16), lineWidth: 1)
        }
        .shadow(color: ScanovaPalette.accent.opacity(0.18), radius: 24, x: 0, y: 16)
    }

    private var planChooser: some View {
        VStack(alignment: .leading, spacing: 14) {
            ScanovaSectionTitle(
                "Choose Your Plan",
                subtitle: "Pick a flexible monthly plan or choose annual access for the best long-term value."
            )

            ForEach(orderedPlans) { plan in
                planCard(for: plan)
            }

            Text("Cancel anytime. Premium access works across merge, protect, reorder, and export tools.")
                .font(ScanovaTypography.caption)
                .foregroundStyle(ScanovaPalette.inkMuted)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 4)
        }
    }

    private func planCard(for plan: SubscriptionService.ProductDisplay) -> some View {
        let isSelected = selectedPlan?.id == plan.id

        return Button {
            selectedProductID = plan.id
        } label: {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Text(plan.shortPlanName)
                                .font(ScanovaTypography.sectionTitle)
                                .foregroundStyle(ScanovaPalette.ink)

                            if let badgeText = planBadgeText(for: plan) {
                                Text(badgeText)
                                    .font(ScanovaTypography.caption)
                                    .foregroundStyle(ScanovaPalette.accentDark)
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 5)
                                    .background(ScanovaPalette.accentSoft.opacity(0.92), in: Capsule(style: .continuous))
                            }
                        }

                        Text(plan.subtitle)
                            .font(ScanovaTypography.supporting)
                            .foregroundStyle(ScanovaPalette.inkMuted)
                            .multilineTextAlignment(.leading)
                    }

                    Spacer(minLength: 10)

                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 21, weight: .semibold))
                        .foregroundStyle(isSelected ? ScanovaPalette.accent : ScanovaPalette.line)
                        .padding(8)
                        .background(Color.white.opacity(isSelected ? 0.86 : 0.52), in: Circle())
                }

                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(plan.price)
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(ScanovaPalette.ink)

                        Text(plan.billingDescription)
                            .font(ScanovaTypography.caption)
                            .foregroundStyle(ScanovaPalette.inkMuted)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 6) {
                        Text(plan.isPrimary ? "Best for repeat scanning" : "Flexible monthly access")
                            .font(ScanovaTypography.caption)
                            .foregroundStyle(ScanovaPalette.inkMuted)
                            .multilineTextAlignment(.trailing)

                        Text(plan.isPrimary ? "Annual savings" : "Cancel anytime")
                            .font(ScanovaTypography.caption)
                            .foregroundStyle(isSelected ? ScanovaPalette.accentDark : ScanovaPalette.inkSoft)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                (isSelected ? ScanovaPalette.accentSoft.opacity(0.96) : Color.white.opacity(0.72)),
                                in: Capsule(style: .continuous)
                            )
                    }
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: isSelected
                                ? [Color.white.opacity(0.98), ScanovaPalette.accentSoft.opacity(0.98)]
                                : [Color.white.opacity(0.88), Color.white.opacity(0.72)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .stroke(isSelected ? ScanovaPalette.accent : Color.white.opacity(0.42), lineWidth: isSelected ? 2 : 1)
            }
            .shadow(color: isSelected ? ScanovaPalette.accent.opacity(0.14) : Color.black.opacity(0.04), radius: 16, x: 0, y: 10)
        }
        .buttonStyle(.plain)
    }

    private var purchaseButtonTitle: String {
        guard !subscriptionService.isSubscribed else { return "Continue to Scanova" }
        return selectedPlan?.hasFreeTrial == true ? "Start Free Trial" : "Continue with Pro"
    }

    private var selectedPlanSummary: String? {
        guard let selectedPlan, !subscriptionService.isSubscribed else { return nil }
        return selectedPlan.billingDescription
    }

    private var footerActions: some View {
        VStack(spacing: 14) {
            Button {
                Task {
                    if subscriptionService.isSubscribed {
                        router.showWorkflow()
                    } else if let selectedProductID {
                        await subscriptionService.purchase(productID: selectedProductID)
                    } else {
                        await subscriptionService.purchasePrimaryOffer()
                    }
                }
            } label: {
                if subscriptionService.isPurchasing {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else {
                    Text(purchaseButtonTitle)
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(ScanovaPrimaryButtonStyle())
            .disabled(subscriptionService.isPurchasing || (!subscriptionService.isSubscribed && selectedPlan == nil))

            if let selectedPlanSummary {
                Text(selectedPlanSummary)
                    .font(ScanovaTypography.caption)
                    .foregroundStyle(ScanovaPalette.inkMuted)
                    .frame(maxWidth: .infinity, alignment: .center)
            }

            if !subscriptionService.isSubscribed {
                HStack(spacing: 12) {
                    Button("Restore Purchases") {
                        Task {
                            await subscriptionService.restorePurchases()
                        }
                    }
                    .buttonStyle(ScanovaSecondaryButtonStyle())

                    Button("Continue Free") {
                        subscriptionService.clearRequestedFeature()
                        router.showWorkflow()
                    }
                    .buttonStyle(ScanovaSecondaryButtonStyle())
                }
            }

            planDetailsSection

            HStack(spacing: 12) {
                Button("Privacy") {
                    presentedDetailSheet = .privacy
                }
                .buttonStyle(ScanovaGhostButtonStyle())

                Button("Terms") {
                    presentedDetailSheet = .terms
                }
                .buttonStyle(ScanovaGhostButtonStyle())

                Button("Support") {
                    presentedDetailSheet = .support
                }
                .buttonStyle(ScanovaGhostButtonStyle())
            }
            .frame(maxWidth: .infinity)

            Text(subscriptionService.statusMessage)
                .font(ScanovaTypography.supporting)
                .foregroundStyle(ScanovaPalette.inkMuted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
    }

    private var activeAccessCard: some View {
        ScanovaCard(accent: ScanovaPalette.success) {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Pro Active")
                        .font(ScanovaTypography.sectionTitle)
                        .foregroundStyle(ScanovaPalette.ink)

                    Text("Your premium tools are unlocked across export, page management, and document editing.")
                        .font(ScanovaTypography.supporting)
                        .foregroundStyle(ScanovaPalette.inkMuted)
                }

                Spacer(minLength: 8)

                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(ScanovaPalette.success)
            }

            Button("Manage Subscription") {
                openManageSubscriptions()
            }
            .buttonStyle(ScanovaCardActionButtonStyle())
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private var planDetailsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            ScanovaSectionTitle(
                subscriptionService.isSubscribed ? "Everything in Pro" : "Everything in Scanova Pro",
                subtitle: subscriptionService.isSubscribed
                    ? "Your plan unlocks advanced editing, safer sharing, and more control over every document."
                    : "Upgrade for cleaner page editing, safer export, and polished document tools in one place."
            )

            proFeaturesCard
        }
        .padding(.top, 6)
    }

    private var proFeaturesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(subscriptionService.isSubscribed ? "Your Premium Toolkit" : "What You Unlock")
                .font(ScanovaTypography.sectionTitle)
                .foregroundStyle(ScanovaPalette.ink)

            ForEach(SubscriptionService.PremiumFeature.allCases) { feature in
                VStack(alignment: .leading, spacing: 3) {
                    Text(feature.title)
                        .font(ScanovaTypography.bodyEmphasis)
                        .foregroundStyle(ScanovaPalette.ink)

                    Text(feature.description)
                        .font(ScanovaTypography.supporting)
                        .foregroundStyle(ScanovaPalette.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 2)
            }
        }
        .padding(18)
        .background(
            LinearGradient(
                colors: [
                    Color.white.opacity(0.94),
                    Color(red: 0.31, green: 0.55, blue: 1.0).opacity(0.12)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 28, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.white.opacity(0.58), lineWidth: 1)
        }
    }

    private var premiumEyebrow: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 11, weight: .bold))
            Text(subscriptionService.isSubscribed ? "Premium Active" : "Premium Access")
                .font(ScanovaTypography.caption)
        }
        .foregroundStyle(.white.opacity(0.92))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.12), in: Capsule(style: .continuous))
    }

    private var premiumOrb: some View {
        ZStack {
            Circle()
                .fill(Color.white.opacity(0.14))
                .frame(width: 72, height: 72)

            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.96), ScanovaPalette.accentSoft.opacity(0.86)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 48, height: 48)

            Image(systemName: subscriptionService.isSubscribed ? "checkmark.seal.fill" : "sparkles")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(subscriptionService.isSubscribed ? ScanovaPalette.success : ScanovaPalette.accent)
        }
    }

    private var heroHighlights: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                premiumHighlight(title: "Merge", symbol: "square.stack.3d.up")
                premiumHighlight(title: "Protect", symbol: "lock")
                premiumHighlight(title: "Reorder", symbol: "arrow.up.arrow.down")
            }

            HStack(spacing: 8) {
                premiumHighlight(title: "Compress", symbol: "arrow.down.right.and.arrow.up.left")
                premiumHighlight(title: "Sign", symbol: "signature")
                premiumHighlight(title: "Stamp", symbol: "seal")
            }
        }
    }

    private func openManageSubscriptions() {
        guard let subscriptionsURL = URL(string: "https://apps.apple.com/account/subscriptions") else {
            return
        }

        openURL(subscriptionsURL)
    }

    private func premiumHighlight(title: String, symbol: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
            Text(title)
                .font(ScanovaTypography.caption)
        }
        .foregroundStyle(.white.opacity(0.88))
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color.white.opacity(0.10), in: Capsule(style: .continuous))
    }

    private func heroOfferStrip(for plan: SubscriptionService.ProductDisplay) -> some View {
        HStack(spacing: 10) {
            Image(systemName: plan.hasFreeTrial ? "gift.fill" : "seal.fill")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(plan.hasFreeTrial ? ScanovaPalette.accentDark : ScanovaPalette.success)
                .frame(width: 28, height: 28)
                .background(Color.white.opacity(0.92), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(plan.hasFreeTrial ? "Annual plan includes a 7-day free trial" : "Choose your premium plan")
                    .font(ScanovaTypography.caption)
                    .foregroundStyle(.white)

                Text(plan.hasFreeTrial ? "Then \(plan.billingDescription)" : plan.billingDescription)
                    .font(ScanovaTypography.caption)
                    .foregroundStyle(.white.opacity(0.78))
            }

            Spacer(minLength: 8)
        }
        .padding(12)
        .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.14), lineWidth: 1)
        }
    }

    private func planBadgeText(for plan: SubscriptionService.ProductDisplay) -> String? {
        if let badgeText = plan.badgeText {
            return badgeText
        }

        if plan.isPrimary {
            return "Best value"
        }

        return nil
    }

    private var orderedPlans: [SubscriptionService.ProductDisplay] {
        subscriptionService.productDisplays.sorted { lhs, rhs in
            if lhs.isPrimary == rhs.isPrimary {
                return lhs.title < rhs.title
            }

            return lhs.isPrimary && !rhs.isPrimary
        }
    }

    private var selectedPlan: SubscriptionService.ProductDisplay? {
        let plans = orderedPlans
        if let selectedProductID {
            return plans.first(where: { $0.id == selectedProductID })
        }

        return plans.first(where: \.isPrimary) ?? plans.first
    }

    private func syncSelectionWithProducts() {
        guard !orderedPlans.isEmpty else {
            selectedProductID = nil
            return
        }

        if let selectedProductID,
           orderedPlans.contains(where: { $0.id == selectedProductID }) {
            return
        }

        self.selectedProductID = orderedPlans.first(where: \.isPrimary)?.id ?? orderedPlans.first?.id
    }

    private var paywallHeadline: String {
        if subscriptionService.isSubscribed {
            return "Scanova Pro is active."
        }

        if let requestedFeature = subscriptionService.lastRequestedFeature {
            return "\(requestedFeature.title) is part of Scanova Pro."
        }

        return "Premium editing, protection, and export in one plan."
    }

    private var paywallSupportText: String {
        if subscriptionService.isSubscribed {
            return "Your subscription is ready across the export and document editing flow."
        }

        if let requestedFeature = subscriptionService.lastRequestedFeature {
            return requestedFeature.description
        }

        return "Merge, protect, compress, annotate, and control every saved page with one Scanova Pro plan."
    }
}

private struct ScanovaCardActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold, design: .rounded))
            .foregroundStyle(ScanovaPalette.ink)
            .lineLimit(1)
            .minimumScaleFactor(0.78)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(configuration.isPressed ? 0.80 : 0.92))
            )
            .overlay {
                Capsule(style: .continuous)
                    .stroke(Color.white.opacity(0.72), lineWidth: 1)
            }
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
    }
}
