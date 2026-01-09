import Foundation
import CartKitCore

public extension CartConfiguration {

    static func configured(
        storage: CartStoragePreference = .automatic,
        pricingEngine: CartPricingEngine = DefaultCartPricingEngine(),
        promotionEngine: PromotionEngine = DefaultPromotionEngine(),
        validationEngine: CartValidationEngine = DefaultCartValidationEngine(),
        conflictResolver: CartConflictResolver? = nil,
        catalogConflictDetector: CartCatalogConflictDetector = NoOpCartCatalogConflictDetector(),
        analytics: CartAnalyticsSink = NoOpCartAnalyticsSink()
    ) async throws -> CartConfiguration {

        let store = try await CartStoreFactory.makeStore(preference: storage)

        return CartConfiguration(
            cartStore: store,
            pricingEngine: pricingEngine,
            promotionEngine: promotionEngine,
            validationEngine: validationEngine,
            conflictResolver: conflictResolver,
            catalogConflictDetector: catalogConflictDetector,
            analyticsSink: analytics
        )
    }
}
