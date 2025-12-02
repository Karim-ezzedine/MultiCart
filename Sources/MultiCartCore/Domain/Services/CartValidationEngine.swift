/// Validates cart and item operations before they are accepted/persisted.
///
/// Called by CartManager:
/// - before add/update/remove item operations,
/// - before status changes,
/// - optionally before saving a cart.
public protocol CartValidationEngine: Sendable {
    
    /// Validate a full cart (status, invariants, limits, etc.).
    func validate(cart: Cart) async -> CartValidationResult
    
    /// Validate a proposed item change within a cart.
    ///
    /// CartManager will:
    /// 1. Build a prospective cart with the proposed item change.
    /// 2. Ask the engine if that new state is acceptable.
    func validateItemChange(
        in cart: Cart,
        proposedItem: CartItem
    ) async -> CartValidationResult
}
