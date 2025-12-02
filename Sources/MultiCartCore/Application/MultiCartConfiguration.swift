/// Configuration object that bundles all dependencies needed by `CartManager`.
///
/// This is the "composition root" contract for the SDK:
/// host apps (or storage modules) provide concrete implementations for
/// ports and domain services, and `CartManager` uses only those abstractions.
public struct MultiCartConfiguration: Sendable {

    public let cartStore: CartStore
    public let pricingEngine: CartPricingEngine
    public let promotionEngine: PromotionEngine
    public let validationEngine: CartValidationEngine
    public let conflictResolver: CartConflictResolver
    public let analyticsSink: CartAnalyticsSink

    public init(
        cartStore: CartStore,
        pricingEngine: CartPricingEngine,
        promotionEngine: PromotionEngine,
        validationEngine: CartValidationEngine,
        conflictResolver: CartConflictResolver,
        analyticsSink: CartAnalyticsSink
    ) {
        self.cartStore = cartStore
        self.pricingEngine = pricingEngine
        self.promotionEngine = promotionEngine
        self.validationEngine = validationEngine
        self.conflictResolver = conflictResolver
        self.analyticsSink = analyticsSink
    }
}
