/// Applies promotions / discounts to a cart before pricing.
///
/// Used by:
/// - Pricing flows inside CartManager prior to CartPricingEngine.
///
/// Default implementation in the SDK will be a no-op engine that returns
/// the cart unchanged, so promos are opt-in.
public protocol PromotionEngine: Sendable {
    
    /// Return a modified cart with promotions applied (e.g. adjusted prices,
    /// attached promo metadata, etc.).
    func applyPromotions(to cart: Cart) async throws -> Cart
}
