/// Handles situations where the cart becomes inconsistent with the
/// current business / catalog state (removed items, price changes, etc.).
///
/// Called by CartManager in flows that detect conflicts, for example:
/// - after refreshing catalog data and finding missing products,
/// - when prices have diverged from the current store catalog,
/// - when new business rules invalidate the cart configuration.
public protocol CartConflictResolver: Sendable {
    
    /// Given a conflicting cart + reason, decide how to proceed.
    func resolveConflict(
        for cart: Cart,
        reason: CartError
    ) async -> CartConflictResolution
}
