/// Applies an array of promotions or discounts to the given cart totals.
///
/// Used by:
/// - Pricing flows inside `CartManager` prior to `CartPricingEngine`.
///
/// The promotion engine is an extension point:
/// - It can evaluate and apply one or more promotions to the current cart totals,
/// - and adjust fields such as delivery fee, subtotal, or discounts as needed,
///   without assuming the user is logged in.
public protocol PromotionEngine: Sendable {
    
    /// Applies the provided promotions to an existing `CartTotals` value.
    ///
    /// Typical responsibilities:
    /// - inspect the incoming `promotions` to determine applicable discounts,
    /// - update the provided `CartTotals` accordingly (e.g. modify subtotal,
    ///   delivery fee, or grand total),
    /// - ensure the resulting totals are correctly clamped (e.g. non-negative).
    ///
    /// - Parameters:
    ///   - promotions: An array  of `PromotionKind` values to apply.
    ///   - cartTotals: The current computed cart totals before promotions.
    /// - Returns: A new `CartTotals` instance reflecting all applied promotions.
    /// - Throws: Any error if promotion evaluation or computation fails.
    func applyPromotions(
        _ promotions: [PromotionKind],
        to cartTotals: CartTotals
    ) async throws -> CartTotals
}
