import Foundation

/// High-level facade / application service for working with carts.
///
/// Responsibilities:
/// - Enforce "one active cart per (storeID, profileID?)" at the API level
/// - Orchestrate domain services (validation, promotions, pricing, conflicts).
/// - Persist changes via CartStore and emit analytics events.
///
/// `CartManager` is implemented as an `actor` to provide safe concurrent
/// access from multiple tasks.
public actor CartManager {
    
    // MARK: - Dependencies
    
    private let config: MultiCartConfiguration
    
    // MARK: - Init
    
    public init(configuration: MultiCartConfiguration) {
        self.config = configuration
    }
    
    // MARK: - Cart lifecycle
    
    /// Creates a new cart for the given store + optional profile.
    @discardableResult
    private func createCart(
        storeID: StoreID,
        profileID: UserProfileID? = nil,
        displayName: String? = nil,
        context: String? = nil,
        storeImageURL: URL? = nil,
        metadata: [String: String] = [:]
    ) async throws -> Cart {
        let now = Date()
        
        let cart = Cart(
            id: CartID.generate(),
            storeID: storeID,
            profileID: profileID,
            items: [],
            status: .active,
            createdAt: now,
            updatedAt: now,
            metadata: metadata,
            displayName: displayName,
            context: context,
            storeImageURL: storeImageURL
        )
        
        try await config.cartStore.saveCart(cart)
        config.analyticsSink.cartCreated(cart)
        
        return cart
    }
    
    /// Ensures there is a single active cart for the given scope.
    ///
    /// If an active cart already exists, it is returned.
    /// If not, a new empty active cart is created.
    @discardableResult
    public func setActiveCart(
        storeID: StoreID,
        profileID: UserProfileID? = nil
    ) async throws -> Cart {
        // Try to find an existing active cart for this scope.
        if let cart = try await getActiveCart(storeID: storeID, profileID: profileID) {
            return cart
        }
        
        // No active cart? Create a new one.
        let newCart = try await createCart(
            storeID: storeID,
            profileID: profileID
        )
        
        return newCart
    }
    
    /// Returns the active cart for a given scope, if any.
    public func getActiveCart(
        storeID: StoreID,
        profileID: UserProfileID? = nil
    ) async throws -> Cart? {
        let query = CartQuery.active(storeID: storeID, profileID: profileID)
        let carts = try await config.cartStore.fetchCarts(
            matching: query,
            limit: 1
        )
        return carts.first
    }
    
    /// Updates the status of a cart, enforcing basic lifecycle rules.
    ///
    /// Allowed transitions:
    /// - `.active` → `.checkedOut`, `.cancelled`, `.expired`
    /// - Any status → same status (no-op)
    ///
    /// Once a cart is non-active, it is treated as terminal and its status
    /// cannot be changed again. This rule applies equally to guest and
    /// logged-in carts.
    ///
    /// - Parameter cartID: Identifier of the cart to update.
    /// - Parameter newStatus: The desired new status.
    /// - Returns: The updated cart after persistence and analytics.
    /// - Throws: `MultiCartError.conflict` if the cart is missing or the
    ///           transition is not allowed.
    @discardableResult
    public func updateStatus(
        for cartID: CartID,
        to newStatus: CartStatus
    ) async throws -> Cart {
        var cart = try await loadCartForStatusChange(id: cartID)
        
        let oldStatus = cart.status
        try ensureValidStatusTransition(from: oldStatus, to: newStatus)
        
        // If nothing changes, short-circuit.
        if oldStatus == newStatus {
            return cart
        }
        
        cart.status = newStatus
        let updatedCart = try await saveCartAfterMutation(cart)
        
        // If we are moving away from `.active`, signal that there is no
        // longer an active cart for this scope. (A new one can be created
        // later via `setActiveCart`.)
        if oldStatus == .active, newStatus != .active {
            config.analyticsSink.activeCartChanged(
                newActiveCartId: nil,
                storeId: updatedCart.storeID,
                profileId: updatedCart.profileID
            )
        }
        
        return updatedCart
    }
    
    /// Updates cart-level metadata (name, context, image, metadata).
    ///
    /// This only operates on active carts; non-active carts will cause a conflict error.
    /// Passing `nil` for parameters keeps the existing value as-is.
    @discardableResult
    public func updateCartDetails(
        cartID: CartID,
        displayName: String? = nil,
        context: String? = nil,
        storeImageURL: URL? = nil,
        metadata: [String: String]? = nil
    ) async throws -> Cart {
        var cart = try await loadMutableCart(for: cartID)
        
        if let displayName {
            cart.displayName = displayName
        }
        if let context {
            cart.context = context
        }
        if let storeImageURL {
            cart.storeImageURL = storeImageURL
        }
        if let metadata {
            cart.metadata = metadata
        }
        
        let updatedCart = try await saveCartAfterMutation(cart)
        return updatedCart
    }
    
    /// Deletes a cart by its identifier.
    ///
    /// - Behavior:
    ///   - If the cart does not exist, the operation is a no-op (idempotent).
    ///   - If it exists, it is removed from storage and `cartDeleted` is emitted.
    ///   - If the deleted cart was active for its scope, `activeCartChanged`
    ///     is emitted with `newActiveCartId == nil`.
    public func deleteCart(id: CartID) async throws {
        guard let cart = try await config.cartStore.loadCart(id: id) else {
            // Already gone; treat as successful.
            return
        }
        
        try await config.cartStore.deleteCart(id: id)
        config.analyticsSink.cartDeleted(id: id)
        
        if cart.status == .active {
            config.analyticsSink.activeCartChanged(
                newActiveCartId: nil,
                storeId: cart.storeID,
                profileId: cart.profileID
            )
        }
    }
    
    // MARK: - Pricing
    
    /// Computes totals for a specific cart ID using the configured pricing engine.
    ///
    /// This loads the cart by ID, builds a pricing context if none is provided,
    /// and delegates the calculation to `CartPricingEngine`.
    ///
    /// - Parameters:
    ///   - cartID: The identifier of the cart to price.
    ///   - context: Optional pricing context (fees, tax, discounts, scope).
    ///              If `nil`, a plain context is built from the cart’s
    ///              `storeID` and `profileID`.
    /// - Returns: The `CartTotals` produced by the pricing engine.
    /// - Throws:
    ///   - `MultiCartError.conflict` if the cart does not exist.
    ///   - Any error thrown by the underlying `CartPricingEngine`.
    public func getTotals(
        for cartID: CartID,
        context: CartPricingContext? = nil
    ) async throws -> CartTotals {
        guard let cart = try await config.cartStore.loadCart(id: cartID) else {
            throw MultiCartError.conflict(reason: "Cart not found")
        }
        
        // If caller didn’t provide a context, build a plain one from the cart.
        let effectiveContext = context ?? .plain(
            storeID: cart.storeID,
            profileID: cart.profileID
        )
        
        return try await config.pricingEngine.computeTotals(
            for: cart,
            context: effectiveContext
        )
    }
    
    /// Computes totals for the active cart in a given scope.
    ///
    /// The scope (store + optional profile) is taken from the
    /// `CartPricingContext`. If no active cart exists for that scope,
    /// this returns `nil` instead of throwing.
    ///
    /// - Parameter context: Pricing context describing the scope
    ///   (`storeID` / `profileID`) and any fees, tax, or discounts.
    /// - Returns: `CartTotals` for the active cart in that scope, or `nil`
    ///            if no active cart exists.
    /// - Throws: Any error thrown by the underlying `CartPricingEngine`.
    public func getTotalsForActiveCart(
        context: CartPricingContext
    ) async throws -> CartTotals? {
        let cart = try await getActiveCart(
            storeID: context.storeID,
            profileID: context.profileID
        )
        
        guard let cart else { return nil }
        
        return try await config.pricingEngine.computeTotals(
            for: cart,
            context: context
        )
    }
    
    // MARK: - Item operations
    
    /// Adds a new item to the given cart.
    ///
    /// - Returns: A `CartUpdateResult` describing the updated cart and the item
    ///            that was added.
    public func addItem(
        to cartID: CartID,
        item: CartItem
    ) async throws -> CartUpdateResult {
        var cart = try await loadMutableCart(for: cartID)
        
        try await validateItemChange(in: cart, item: item)
        
        cart.items.append(item)
        
        let updatedCart = try await saveCartAfterMutation(cart)
        config.analyticsSink.itemAdded(item, in: updatedCart)
        
        return CartUpdateResult(
            cart: updatedCart,
            removedItems: [],
            changedItems: [item]
        )
    }
    
    /// Updates an existing item in the given cart.
    ///
    /// Matching is done by `CartItem.id`.
    /// - Returns: A `CartUpdateResult` describing the updated cart and the item
    ///            that was changed.
    public func updateItem(
        in cartID: CartID,
        item updatedItem: CartItem
    ) async throws -> CartUpdateResult {
        var cart = try await loadMutableCart(for: cartID)
        
        guard let index = cart.items.firstIndex(where: { $0.id == updatedItem.id }) else {
            throw MultiCartError.conflict(reason: "Item not found in cart")
        }
        
        try await validateItemChange(in: cart, item: updatedItem)
        
        cart.items[index] = updatedItem
        
        let updatedCart = try await saveCartAfterMutation(cart)
        config.analyticsSink.itemUpdated(updatedItem, in: updatedCart)
        
        return CartUpdateResult(
            cart: updatedCart,
            removedItems: [],
            changedItems: [updatedItem]
        )
    }
    
    /// Removes an item from the given cart by its identifier.
    ///
    /// - Returns: A `CartUpdateResult` describing the updated cart and the item
    ///            that was removed.
    public func removeItem(
        from cartID: CartID,
        itemID: CartItemID
    ) async throws -> CartUpdateResult {
        var cart = try await loadMutableCart(for: cartID)
        
        guard let index = cart.items.firstIndex(where: { $0.id == itemID }) else {
            throw MultiCartError.conflict(reason: "Item not found in cart")
        }
        
        let removedItem = cart.items.remove(at: index)
        
        let updatedCart = try await saveCartAfterMutation(cart)
        config.analyticsSink.itemRemoved(itemId: itemID, from: updatedCart)
        
        return CartUpdateResult(
            cart: updatedCart,
            removedItems: [removedItem],
            changedItems: []
        )
    }
    
    // MARK: - Helpers
    
    /// Loads a cart and enforces that it is present and mutable.
    ///
    /// Currently this means:
    /// - The cart exists in the underlying store.
    /// - The cart has `status == .active`.
    ///
    /// Non-existing or non-active carts result in a `MultiCartError.conflict`
    /// so that callers know the operation cannot proceed on this cart.
    private func loadMutableCart(for id: CartID) async throws -> Cart {
        guard let cart = try await config.cartStore.loadCart(id: id) else {
            throw MultiCartError.conflict(reason: "Cart not found")
        }
        
        guard cart.status == .active else {
            throw MultiCartError.conflict(reason: "Cart is not active")
        }
        
        return cart
    }
    
    /// Loads a cart for status changes without enforcing `status == .active`.
    ///
    /// Status transitions themselves are governed by
    /// `ensureValidStatusTransition(from:to:)`.
    private func loadCartForStatusChange(id: CartID) async throws -> Cart {
        guard let cart = try await config.cartStore.loadCart(id: id) else {
            throw MultiCartError.conflict(reason: "Cart not found")
        }
        return cart
    }
    
    /// Validates a proposed item change against the configured validation engine.
    ///
    /// This helper calls `CartValidationEngine.validateItemChange(in:proposedItem:)`
    /// and translates the resulting `CartValidationResult` into a `MultiCartError`
    /// when the change is not allowed.
    ///
    /// - Parameters:
    ///   - cart: The current cart snapshot before applying the change.
    ///   - item: The item state we want to apply to the cart.
    /// - Throws: `MultiCartError.validationFailed` when the validation engine
    ///           reports an invalid change.
    private func validateItemChange(
        in cart: Cart,
        item: CartItem
    ) async throws {
        let result = await config.validationEngine.validateItemChange(
            in: cart,
            proposedItem: item
        )
        
        switch result {
        case .valid:
            return
        case .invalid(let reason):
            throw MultiCartError.validationFailed(reason: reason)
        }
    }
    
    /// Persists a mutated cart and emits a `cartUpdated` analytics event.
    ///
    /// This helper is responsible for:
    /// - bumping `updatedAt` to the current time,
    /// - saving the cart through the configured `CartStore`,
    /// - notifying the `CartAnalyticsSink` that the cart was updated.
    ///
    /// - Parameter cart: The cart after in-memory mutations.
    /// - Returns: The saved cart, with its `updatedAt` field refreshed.
    /// - Throws: Any error thrown by the underlying `CartStore`.
    private func saveCartAfterMutation(_ cart: Cart) async throws -> Cart {
        var mutableCart = cart
        mutableCart.updatedAt = Date()
        try await config.cartStore.saveCart(mutableCart)
        config.analyticsSink.cartUpdated(mutableCart)
        return mutableCart
    }
    
    /// Enforces the allowed cart status transitions.
    ///
    /// Current rules:
    /// - A cart in `.active` may transition to any non-active state.
    /// - A cart may remain in its current state (no-op).
    /// - Non-active states are terminal and cannot transition to any other
    ///   state (including back to `.active`).
    private func ensureValidStatusTransition(
        from oldStatus: CartStatus,
        to newStatus: CartStatus
    ) throws {
        if oldStatus == newStatus {
            return
        }
        
        if oldStatus == .active, newStatus != .active {
            return
        }
        
        throw MultiCartError.conflict(reason: "Invalid cart status transition")
    }
}
