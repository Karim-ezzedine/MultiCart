import Foundation

/// Describes the external inputs needed to price a cart.
///
/// This keeps things like fees/taxes/config outside the Cart entity
/// and makes the pricing engine easier to swap / test.
public struct CartPricingContext: Hashable, Codable, Sendable {
    
    /// Store scope for this pricing run (usually matches `cart.storeID`).
    public let storeID: StoreID
    
    /// Optional profile scope (nil = guest).
    public let profileID: UserProfileID?
    
    /// Flat service fee (e.g. app/service fee), if any.
    public let serviceFee: Money?
    
    /// Delivery fee, if any.
    public let deliveryFee: Money?
    
    /// Percentage tax rate applied on the merchandise subtotal.
    /// Example: 0.11 = 11% VAT.
    public let taxRate: Decimal
    
    /// Extra cart-level discount (e.g. promo code).
    /// Positive amount means “subtract this from the total”.
    public let manualDiscount: Money?
    
    public init(
        storeID: StoreID,
        profileID: UserProfileID? = nil,
        serviceFee: Money? = nil,
        deliveryFee: Money? = nil,
        taxRate: Decimal = 0,
        manualDiscount: Money? = nil
    ) {
        self.storeID = storeID
        self.profileID = profileID
        self.serviceFee = serviceFee
        self.deliveryFee = deliveryFee
        self.taxRate = taxRate
        self.manualDiscount = manualDiscount
    }
    
    /// Convenience for “no extra fees / tax / discount”.
    public static func plain(
        storeID: StoreID,
        profileID: UserProfileID? = nil
    ) -> CartPricingContext {
        CartPricingContext(
            storeID: storeID,
            profileID: profileID,
            serviceFee: nil,
            deliveryFee: nil,
            taxRate: 0,
            manualDiscount: nil
        )
    }
}
