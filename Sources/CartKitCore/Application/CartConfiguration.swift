/// Configuration object that bundles all dependencies needed by `CartManager`.
///
/// This is the "composition root" contract for the SDK:
/// host apps (or storage modules) provide concrete implementations for
/// ports and domain services, and `CartManager` uses only those abstractions.
public struct CartConfiguration: Sendable {

    public let cartStore: CartStore
    public let pricingEngine: CartPricingEngine
    public let promotionEngine: PromotionEngine
    public let validationEngine: CartValidationEngine
    public let conflictResolver: CartConflictResolver?
    public let catalogConflictDetector: CartCatalogConflictDetector
    public let analyticsSink: CartAnalyticsSink

    public init(
        cartStore: CartStore,
        pricingEngine: CartPricingEngine = DefaultCartPricingEngine(),
        promotionEngine: PromotionEngine = DefaultPromotionEngine(),
        validationEngine: CartValidationEngine = DefaultCartValidationEngine(),
        conflictResolver: CartConflictResolver? = nil,
        catalogConflictDetector: CartCatalogConflictDetector = NoOpCartCatalogConflictDetector(),
        analyticsSink: CartAnalyticsSink = NoOpCartAnalyticsSink()
    ) {
        self.cartStore = cartStore
        self.pricingEngine = pricingEngine
        self.promotionEngine = promotionEngine
        self.validationEngine = validationEngine
        self.conflictResolver = conflictResolver
        self.catalogConflictDetector = catalogConflictDetector
        self.analyticsSink = analyticsSink
    }
}
