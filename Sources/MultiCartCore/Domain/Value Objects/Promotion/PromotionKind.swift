import Foundation

/// Machine-readable type + parameters of a promotion.
public enum PromotionKind: Hashable, Codable, Sendable {

    /// Makes the delivery fee effectively zero for this cart.
    case freeDelivery

    /// Percentage discount on the cart (e.g. 0.10 = 10% off).
    ///
    /// Interpretation (cart vs items vs delivery) is left to the
    /// promotion/pricing engines; for v1 we treat it as "off cart total".
    case percentageOffCart(Decimal)

    /// Fixed-amount discount on the cart total (e.g. 5 USD off).
    case fixedAmountOffCart(Money)

    /// Catch-all for app-specific or more complex rules.
    ///
    /// `kind` can be something like "FREE SERVICE FEE", "FREE TAX", etc.
    ///  We can add those kind in V2
    case custom(kind: String, value: Decimal)
}
