/// Receives cart-related events so the host app can plug into analytics/logging.
///
/// Called by CartManager **after successful operations**:
/// - cartCreated / cartUpdated / cartDeleted
/// - active cart switches
/// - item added/updated/removed.
///
/// Methods are synchronous and non-throwing on purpose; implementations
/// should offload heavy work to their own queues if needed.
public protocol CartAnalyticsSink: Sendable {
    
    // MARK: - Cart lifecycle
    
    func cartCreated(_ cart: Cart)
    func cartUpdated(_ cart: Cart)
    func cartDeleted(id: CartID)
    
    func activeCartChanged(
        newActiveCartId: CartID?,
        storeId: StoreID,
        profileId: UserProfileID?
    )
    
    // MARK: - Items
    
    func itemAdded(_ item: CartItem, in cart: Cart)
    func itemUpdated(_ item: CartItem, in cart: Cart)
    func itemRemoved(
        itemId: CartItemID,
        from cart: Cart
    )
}
