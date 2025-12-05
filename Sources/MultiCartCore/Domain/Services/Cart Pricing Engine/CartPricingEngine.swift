/// Strategy for computing cart totals from a cart snapshot + pricing context.
///
/// Used by:
/// - `CartManager` pricing APIs (e.g. `getTotals(for:context:)`,
///   `getTotalsForActiveCart(context:)`).
/// - Any flow that needs up-to-date totals for a given cart without
///   mutating the cart itself.
///
/// Typical flow:
/// 1. Load a persisted `Cart`.
/// 2. Optionally run `PromotionEngine.applyPromotions(to:)` to produce a
///    promoted cart snapshot.
/// 3. Build a `CartPricingContext` (fees, tax, discounts, store/profile scope).
/// 4. Call `CartPricingEngine.computeTotals(for:context:)` to get `CartTotals`.
public protocol CartPricingEngine: Sendable {
    
    /// Computes totals for the given cart under the provided pricing context.
    ///
    /// - Parameters:
    ///   - cart: The cart snapshot to price (usually already validated
    ///           and optionally promotion-adjusted).
    ///   - context: External pricing inputs (fees, tax rates, discounts,
    ///              store/profile scope).
    /// - Returns: Calculated `CartTotals` for this cart + context.
    func computeTotals(
        for cart: Cart,
        context: CartPricingContext
    ) async throws -> CartTotals
}

/// Convenience overload for callers that don't need to customize the context.
///
/// Builds a plain `CartPricingContext` from the cart’s `storeID`/`profileID`
/// and delegates to `computeTotals(for:context:)`.
public extension CartPricingEngine {
    func computeTotals(for cart: Cart) async throws -> CartTotals {
        let context = CartPricingContext.plain(
            storeID: cart.storeID,
            profileID: cart.profileID
        )
        return try await computeTotals(for: cart, context: context)
    }
}

