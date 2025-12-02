/// Describes the outcome of a cart mutation operation.
///
/// This allows callers to understand what changed as a result of the update:
/// - the final cart state,
/// - which items were removed,
/// - which items were changed (added or updated).
public struct CartUpdateResult: Sendable {
    /// The cart after the operation has been applied and persisted.
    public let cart: Cart
    
    /// Items that were removed from the cart as part of this operation.
    public let removedItems: [CartItem]
    
    /// Items that were added or updated as part of this operation.
    public let changedItems: [CartItem]
    
    public init(
        cart: Cart,
        removedItems: [CartItem] = [],
        changedItems: [CartItem] = []
    ) {
        self.cart = cart
        self.removedItems = removedItems
        self.changedItems = changedItems
    }
}
