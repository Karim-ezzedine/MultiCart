/// Computes cart totals from a given cart snapshot.
///
/// Used by:
/// - CartManager.computeTotals(for:)
/// - Any flow that needs up-to-date totals for a cart.
///
/// Typical flow:
/// 1. Start from persisted cart.
/// 2. Optionally run PromotionEngine.applyPromotions(to:).
/// 3. Call CartPricingEngine.computeTotals(for:).
public protocol CartPricingEngine: Sendable {
    func computeTotals(for cart: Cart) async throws -> CartTotals
}
