import Foundation

/// Default, stateless promotion engine used by the SDK.
///
/// Applies a simple set of cart-level rules on top of existing `CartTotals`:
/// - `.freeDelivery`        → sets `deliveryFee` to zero.
/// - `.percentageOffCart`   → applies one or more percentage discounts on `subtotal` (clamped at 0).
/// - `.fixedAmountOffCart`  → subtracts one or more fixed amounts from `subtotal` (clamped at 0).
/// - `.custom`              → ignored for now (no-op).
///
/// The engine then recomputes `grandTotal` as:
/// `subtotal + deliveryFee + serviceFee + tax`.
///
/// This is a pure domain service (no side effects) and the default
/// `PromotionEngine` implementation; apps can inject their own engine
/// via `CartConfiguration` if they need different rules.
public struct DefaultPromotionEngine: PromotionEngine, Sendable {
    
    public init() {}
    
    public func applyPromotions(
        _ promotions: [PromotionKind],
        to cartTotal: CartTotals
    ) async throws -> CartTotals {
        
        // Fast path: no promotions, return unchanged
        guard !promotions.isEmpty else { return cartTotal }
        
        let currency = cartTotal.subtotal.currencyCode
        
        var subtotal = cartTotal.subtotal
        var deliveryFee = cartTotal.deliveryFee
        let serviceFee = cartTotal.serviceFee
        let tax = cartTotal.tax
        
        // freeDelivery → deliveryFee = 0
        if promotions.contains(.freeDelivery) {
            deliveryFee = .zero(currencyCode: currency)
        }
        
        // Aggregate all percentageOffCart discounts.
        // Example: 0.10 + 0.05 = 0.15 total (15% off).
        let totalPercentage: Decimal = promotions
            .compactMap(percentageValue)
            .reduce(0, +)
        
        if totalPercentage > 0 {
            let discountAmount = subtotal.amount * totalPercentage
            let newAmount = subtotal.amount - discountAmount
            let clamped = max(newAmount, 0)
            subtotal = Money(amount: clamped, currencyCode: currency)
        }
        
        // Aggregate all fixedAmountOffCart discounts.
        let totalFixedDiscount: Decimal = promotions
            .compactMap(fixedAmountValue)
            .reduce(0) { partial, money in
                // Ignore negative discounts; accumulate only positive values.
                partial + max(money.amount, 0)
            }
        
        if totalFixedDiscount > 0 {
            let newAmount = subtotal.amount - totalFixedDiscount
            let clamped = max(newAmount, 0)
            subtotal = Money(amount: clamped, currencyCode: currency)
        }
        
        // Recompute grandTotal = subtotal + fees + tax
        let grandTotalAmount =
        subtotal.amount +
        deliveryFee.amount +
        serviceFee.amount +
        tax.amount
        
        let grandTotal = Money(amount: grandTotalAmount, currencyCode: currency)
        
        return CartTotals(
            subtotal: subtotal,
            deliveryFee: deliveryFee,
            serviceFee: serviceFee,
            tax: tax,
            grandTotal: grandTotal
        )
    }
    
    
    // MARK: - Helpers
    
    private func percentageValue(_ kind: PromotionKind) -> Decimal? {
        if case let .percentageOffCart(value) = kind { return value }
        return nil
    }
    
    private func fixedAmountValue(_ kind: PromotionKind) -> Money? {
        if case let .fixedAmountOffCart(money) = kind { return money }
        return nil
    }
}
