import Foundation
import StoreKit

@MainActor
final class SubscriptionService: ObservableObject {
    struct ProductDisplay: Identifiable {
        let id: String
        let title: String
        let subtitle: String
        let price: String
        let isPrimary: Bool
        // Only true when the app has a reliable user-eligibility signal.
        let hasFreeTrial: Bool
        let trialDescription: String?
        let billingDescription: String
        let badgeText: String?

        var shortPlanName: String {
            if id.contains("yearly") {
                return "Annual"
            }

            if id.contains("monthly") {
                return "Monthly"
            }

            return title
        }
    }

    enum PremiumFeature: String, CaseIterable, Identifiable {
        case compress
        case passwordProtection
        case merge
        case split
        case deletePages
        case reorderPages
        case convertToImages
        case insertSignature
        case insertStamp
        case insertShapes

        var id: String { rawValue }

        var title: String {
            switch self {
            case .compress:
                return "Compress PDFs"
            case .passwordProtection:
                return "Password Protect PDFs"
            case .merge:
                return "Merge PDFs"
            case .split:
                return "Split PDFs"
            case .deletePages:
                return "Delete Pages"
            case .reorderPages:
                return "Reorder Pages"
            case .convertToImages:
                return "Convert PDF to Images"
            case .insertSignature:
                return "Insert Signature"
            case .insertStamp:
                return "Insert Stamp"
            case .insertShapes:
                return "Insert Shapes"
            }
        }

        var description: String {
            switch self {
            case .compress:
                return "Shrink large PDFs for quicker sharing and lighter storage."
            case .passwordProtection:
                return "Add a password before you share sensitive PDFs."
            case .merge:
                return "Combine multiple documents into one polished PDF."
            case .split:
                return "Turn selected pages into a clean standalone PDF."
            case .deletePages:
                return "Remove extra pages and save a cleaner revised copy."
            case .reorderPages:
                return "Put pages in the right order and save the updated PDF."
            case .convertToImages:
                return "Create image files from your PDF pages for sharing anywhere."
            case .insertSignature:
                return "Place your signature directly where the page needs it."
            case .insertStamp:
                return "Mark pages with stamps like Approved, Paid, or Confidential."
            case .insertShapes:
                return "Add arrows, circles, and rectangles to call attention clearly."
            }
        }
    }

    @Published private(set) var isSubscribed: Bool
    @Published private(set) var products: [Product] = []
    @Published private(set) var productDisplays: [ProductDisplay] = []
    @Published private(set) var statusMessage = "You’re using the free version."
    @Published private(set) var isLoadingProducts = false
    @Published private(set) var isPurchasing = false
    @Published private(set) var lastRequestedFeature: PremiumFeature?
    private var hasActiveSubscription = false

    private let productIDs = [
        "com.scanova.pro.monthly",
        "com.scanova.pro.yearly"
    ]

    init() {
        isSubscribed = false
    }

    func prepareStore() async {
        await loadProductsIfNeeded()
        await refreshEntitlements()
    }

    func loadProductsIfNeeded() async {
        guard products.isEmpty, !isLoadingProducts else { return }

        isLoadingProducts = true
        defer { isLoadingProducts = false }

        do {
            let loadedProducts = try await Product.products(for: productIDs)
                .sorted { lhs, rhs in
                    lhs.price < rhs.price
                }

            products = loadedProducts
            var displays: [ProductDisplay] = []
            displays.reserveCapacity(loadedProducts.count)

            for product in loadedProducts {
                let displayPrice = resolvedDisplayPrice(for: product)
                let trialDescription = trialDescription(for: product)
                let hasFreeTrial = await introOfferEligibility(for: product)
                displays.append(ProductDisplay(
                    id: product.id,
                    title: product.displayName,
                    subtitle: subtitle(for: product),
                    price: displayPrice,
                    isPrimary: product.id.contains("yearly"),
                    hasFreeTrial: hasFreeTrial,
                    trialDescription: trialDescription,
                    billingDescription: billingDescription(
                        for: product,
                        displayPrice: displayPrice,
                        trialDescription: hasFreeTrial ? trialDescription : nil
                    ),
                    badgeText: badgeText(for: product, hasFreeTrial: hasFreeTrial)
                ))
            }
            productDisplays = displays

            if hasActiveSubscription {
                statusMessage = "Scanova Pro is active."
            } else if loadedProducts.isEmpty {
                statusMessage = "Premium plans aren’t available right now."
            } else if isSubscribed {
                statusMessage = "Scanova Pro is active."
            } else {
                statusMessage = "You’re using the free version."
            }
        } catch {
            statusMessage = "Unable to load premium plans right now."
            products = []
            productDisplays = []
        }
    }

    func refreshEntitlements() async {
        var hasActiveSubscription = false

        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            if productIDs.contains(transaction.productID),
               transaction.revocationDate == nil,
               transaction.expirationDate.map({ $0 > Date() }) ?? true {
                hasActiveSubscription = true
            }
        }

        self.hasActiveSubscription = hasActiveSubscription
        applySubscriptionState()
    }

    func purchasePrimaryOffer() async {
        guard let product = preferredProduct else {
            statusMessage = "Premium plans aren’t available right now."
            return
        }

        await purchase(productID: product.id)
    }

    func purchase(productID: String) async {
        guard let product = products.first(where: { $0.id == productID }) else {
            statusMessage = "Premium plans aren’t available right now."
            return
        }

        isPurchasing = true
        defer { isPurchasing = false }

        do {
            let result = try await product.purchase()

            switch result {
            case .success(let verification):
                guard case .verified(let transaction) = verification else {
                    statusMessage = "We couldn’t verify the purchase. Please try again."
                    return
                }

                await transaction.finish()
                await refreshEntitlements()
            case .userCancelled:
                statusMessage = "Purchase cancelled."
            case .pending:
                statusMessage = "Purchase is pending approval."
            @unknown default:
                statusMessage = "Purchase did not complete."
            }
        } catch {
            statusMessage = "Purchase failed. Please try again."
        }
    }

    func restorePurchases() async {
        do {
            try await AppStore.sync()
            await refreshEntitlements()
            if !isSubscribed {
                statusMessage = "No previous Scanova Pro purchases were found."
            }
        } catch {
            statusMessage = "Restore failed. Please try again."
        }
    }

    func requestPaywall(for feature: PremiumFeature) {
        lastRequestedFeature = feature
    }

    @discardableResult
    func requirePremium(_ feature: PremiumFeature, router: AppRouter) -> Bool {
        guard !isSubscribed else { return true }
        requestPaywall(for: feature)
        router.showPaywall()
        return false
    }

    func clearRequestedFeature() {
        lastRequestedFeature = nil
    }

    var unlockedFeatures: [PremiumFeature] {
        isSubscribed ? PremiumFeature.allCases : []
    }

    private var preferredProduct: Product? {
        products.first(where: { $0.id.contains("yearly") }) ?? products.first
    }

    private func subtitle(for product: Product) -> String {
        if product.id.contains("yearly") {
            return "Best value for repeat scanning and exports."
        }

        if product.id.contains("monthly") {
            return "Flexible access for shorter projects."
        }

        return "Unlock premium editing, protection, and export tools."
    }

    private func billingDescription(for product: Product, displayPrice: String, trialDescription: String?) -> String {
        let billingSuffix: String
        if product.id.contains("yearly") {
            billingSuffix = "/year"
        } else if product.id.contains("monthly") {
            billingSuffix = "/month"
        } else {
            billingSuffix = ""
        }

        let billingPrice = "\(displayPrice)\(billingSuffix)"
        guard trialDescription != nil else { return billingPrice }
        // Keep billing language eligibility-safe until we can verify the user qualifies.
        return billingPrice
    }

    private func resolvedDisplayPrice(for product: Product) -> String {
        let displayPrice = product.displayPrice

        #if DEBUG
        if displayPrice.contains("$"),
           let localizedPrice = debugINRPrice(for: product.price) {
            return localizedPrice
        }
        #endif

        return displayPrice
    }

    private func debugINRPrice(for price: Decimal) -> String? {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = Locale(identifier: "en_IN")
        formatter.currencyCode = "INR"
        formatter.maximumFractionDigits = 0
        formatter.minimumFractionDigits = 0
        return formatter.string(from: price as NSDecimalNumber)
    }

    private func badgeText(for product: Product, hasFreeTrial: Bool) -> String? {
        if hasFreeTrial {
            return "7-Day Free Trial"
        }

        if product.id.contains("yearly") {
            return "Best Value"
        }

        return nil
    }

    private func trialDescription(for product: Product) -> String? {
        guard let introOffer = product.subscription?.introductoryOffer else { return nil }
        guard introOffer.paymentMode == .freeTrial else { return nil }

        let unitLabel: String
        switch introOffer.period.unit {
        case .day:
            unitLabel = introOffer.period.value == 1 ? "day" : "days"
        case .week:
            unitLabel = introOffer.period.value == 1 ? "week" : "weeks"
        case .month:
            unitLabel = introOffer.period.value == 1 ? "month" : "months"
        case .year:
            unitLabel = introOffer.period.value == 1 ? "year" : "years"
        @unknown default:
            unitLabel = "days"
        }

        return "\(introOffer.period.value)-\(unitLabel) free trial"
    }

    private func introOfferEligibility(for product: Product) async -> Bool {
        guard let subscription = product.subscription else { return false }
        guard subscription.introductoryOffer?.paymentMode == .freeTrial else { return false }
        guard #available(iOS 17.0, *) else { return false }
        return await subscription.isEligibleForIntroOffer
    }

    private func applySubscriptionState() {
        isSubscribed = hasActiveSubscription
        statusMessage = isSubscribed ? "Scanova Pro is active." : "You’re using the free version."
    }
}
