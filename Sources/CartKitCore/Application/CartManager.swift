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
    
    private let config: CartConfiguration
    
    // MARK: - Init
    
    public init(configuration: CartConfiguration) {
        self.config = configuration
    }
    
    // MARK: - Cart lifecycle
    
    /// Simple read helper (keeps consumers talking to the facade).
    public func getCart(id: CartID) async throws -> Cart? {
        try await config.cartStore.loadCart(id: id)
    }
    
    /// Creates a new cart for the given store + optional profile.
    @discardableResult
    private func createCart(
        storeID: StoreID,
        profileID: UserProfileID? = nil,
        displayName: String? = nil,
        context: String? = nil,
        storeImageURL: URL? = nil,
        metadata: [String: String] = [:],
        minSubtotal: Money? = nil,
        maxItemCount: Int? = nil,
        status: CartStatus
    ) async throws -> Cart {
        let now = Date()
        
        let cart = Cart(
            id: CartID.generate(),
            storeID: storeID,
            profileID: profileID,
            items: [],
            status: status,
            createdAt: now,
            updatedAt: now,
            metadata: metadata,
            displayName: displayName,
            context: context,
            storeImageURL: storeImageURL,
            minSubtotal: minSubtotal,
            maxItemCount: maxItemCount
        )
        
        return try await persistNewCart(cart, setAsActive: status == .active)
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
            profileID: profileID,
            status: .active
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
    
    /// Updates the status of a cart, enforcing lifecycle and validation rules.
    ///
    /// Allowed transitions:
    /// - `.active` → `.checkedOut`, `.cancelled`, `.expired`
    /// - Any status → same status (no-op)
    ///
    /// Once a cart is non-active, it is treated as terminal and its status
    /// cannot be changed again. This rule applies equally to guest and
    /// logged-in carts.
    ///
    /// When transitioning to `.checkedOut`, the cart is first validated via
    /// the configured `CartValidationEngine.validate(cart:)`. If validation
    /// fails, a `CartError.validationFailed` is thrown.
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
        
        // If we're checking out, enforce full-cart validation first.
        if newStatus == .checkedOut {
            
            guard cart.profileID != nil else {
                throw CartError.validationFailed(reason: "Profile ID is missing, cannot update cart status to checkedOut")
            }
            
            let result = await config.validationEngine.validate(cart: cart)
            switch result {
            case .valid:
                break
            case .invalid(let error):
                throw CartError.validationFailed(reason: error.message)
            }
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
        metadata: [String: String]? = nil,
        minSubtotal: Money? = nil,
        maxItemCount: Int? = nil
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
        if let minSubtotal {
            cart.minSubtotal = minSubtotal
        }
        if let maxItemCount {
            cart.maxItemCount = maxItemCount
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
    
    /// Creates a new active cart by copying a source cart (reorder use case).
    ///
    /// The reorder flow:
    /// - expires the current active cart for the same scope (if any),
    /// - creates a new cart with regenerated `CartItemID`s,
    /// - persists it and emits `activeCartChanged`.
    public func reorder(from sourceCartID: CartID) async throws -> Cart {
        let source = try await loadCartOrThrow(sourceCartID)

        // Enforce one-active-per-scope by expiring the current active cart (if any)
        try await expireActiveCartIfNeeded(storeID: source.storeID, profileID: source.profileID)

        let newCart = makeActiveCartCopy(from: source, profileID: source.profileID)

        return try await persistNewCart(newCart, setAsActive: true)
    }

    /// Migrates the active guest cart to a logged-in profile for a given store.
    ///
    /// Strategies:
    /// - `.move`: re-scopes the same cart to the profile (same `CartID`).
    /// - `.copyAndDelete`: creates a new profile cart copy and deletes the guest cart.
    ///
    /// If the profile already has an active cart for the store, the migration fails with a conflict error.
    public func migrateGuestActiveCart(
        storeID: StoreID,
        to profileID: UserProfileID,
        strategy: GuestMigrationStrategy
    ) async throws -> Cart {

        // Find active guest cart
        guard let guestActive = try await getActiveCart(storeID: storeID) else {
            throw CartError.conflict(
                reason: "No active guest cart found for store \(storeID.rawValue)"
            )
        }

        // Enforce invariant: profile must not already have an active cart
        if try await getActiveCart(storeID: storeID, profileID: profileID) != nil {
            throw CartError.conflict(
                reason: "Profile \(profileID.rawValue) already has an active cart for store \(storeID.rawValue)"
            )
        }

        switch strategy {
        case .move:
            let moved = Cart(
                id: guestActive.id,
                storeID: guestActive.storeID,
                profileID: profileID,
                items: guestActive.items,
                status: .active,
                createdAt: guestActive.createdAt,
                updatedAt: Date(),
                metadata: guestActive.metadata,
                displayName: guestActive.displayName,
                context: guestActive.context,
                storeImageURL: guestActive.storeImageURL,
                minSubtotal: guestActive.minSubtotal,
                maxItemCount: guestActive.maxItemCount
            )

            let saved = try await saveCartAfterMutation(moved)

            config.analyticsSink.activeCartChanged(
                newActiveCartId: saved.id,
                storeId: storeID,
                profileId: profileID
            )

            return saved

        case .copyAndDelete:
            let newCart = makeActiveCartCopy(from: guestActive, profileID: profileID)

            let saved = try await persistNewCart(newCart, setAsActive: true)

            try await deleteCart(id: guestActive.id)

            return saved
        }
    }
    
    // MARK: - Pricing
    
    /// Computes totals for a specific cart ID using the configured
    /// pricing and promotion engines.
    ///
    /// - Parameters:
    ///   - cartID: The identifier of the cart to price.
    ///   - context: Optional pricing context (fees, tax, discounts, scope). If `nil`,
    ///              a plain context is built from the cart’s `storeID` and `profileID`.
    ///   - promotions: Optional map of promotion kinds to their applied metadata. If non-`nil`,
    ///                 promotions will be applied on top of the base totals via the `PromotionEngine`.
    /// - Returns: The final `CartTotals` after pricing and any applied promotions.
    /// - Throws:
    ///   - `CartError.conflict` if the cart does not exist.
    ///   - Any error thrown by the configured `CartPricingEngine` or `PromotionEngine`.
    public func getTotals(
        for cartID: CartID,
        context: CartPricingContext? = nil,
        with promotions: [PromotionKind]? = nil
    ) async throws -> CartTotals {
        let cart = try await loadCartOrThrow(cartID)
        
        // If caller didn’t provide a context, build a plain one from the cart.
        let effectiveContext = context ?? .plain(
            storeID: cart.storeID,
            profileID: cart.profileID
        )
        
        let cartTotals = try await config.pricingEngine.computeTotals(
            for: cart,
            context: effectiveContext
        )
        
        return try await self.applyPromotionsIfAvailable(
            promotions,
            to: cartTotals
        )
    }
    
    /// Computes totals for the active cart in a given scope using the
    /// configured pricing and promotion engines.
    ///
    /// - Parameters:
    ///   - context: Pricing context describing the scope (`storeID` / `profileID`)
    ///              and any fees, tax, or discounts.
    ///   - promotions: Optional map of promotion kinds to their applied metadata.
    ///                 If non-`nil`, promotions will be applied on top of the base
    ///                 totals via the `PromotionEngine`.
    /// - Returns: `CartTotals` for the active cart in that scope (after any promotions),
    ///            or `nil` if no active cart exists.
    /// - Throws: Any error thrown by the configured `CartPricingEngine` or
    ///           `PromotionEngine`.
    public func getTotalsForActiveCart(
        context: CartPricingContext,
        with promotions: [PromotionKind]? = nil
    ) async throws -> CartTotals? {
        let cart = try await getActiveCart(
            storeID: context.storeID,
            profileID: context.profileID
        )
        
        guard let cart else { return nil }
        
        let cartTotals = try await config.pricingEngine.computeTotals(
            for: cart,
            context: context
        )
        
        return try await self.applyPromotionsIfAvailable(
            promotions,
            to: cartTotals
        )
    }
    
    /// Applies promotions to already-computed cart totals, if any are provided.
    ///
    /// This is a small orchestration helper:
    /// - If `promotions` is `nil`, the input `cartTotals` are returned unchanged.
    /// - If `promotions` is non-`nil`, the call is delegated to the configured
    ///   `PromotionEngine.applyPromotions(_:,to:)`.
    ///
    /// This keeps `CartManager` responsible for the flow (pricing → promotions)
    /// while `PromotionEngine` encapsulates the promotion math.
    ///
    /// - Parameters:
    ///   - promotions: Optional map of promotion kinds to applied promotions.
    ///   - cartTotals: Base totals computed by the `CartPricingEngine`.
    /// - Returns: Final `CartTotals` after applying promotions, or the original
    ///            totals when no promotions are provided.
    /// - Throws: Any error thrown by the configured `PromotionEngine`.
    public func applyPromotionsIfAvailable(
        _ promotions: [PromotionKind]? = nil,
        to cartTotals: CartTotals
    ) async throws -> CartTotals {
        if let promotions = promotions {
            return try await config.promotionEngine.applyPromotions(promotions, to: cartTotals)
        }
        else {
            return cartTotals
        }
    }
    
    /// Validates the cart before checkout using the configured validation engine.
    ///
    /// This does **not** change the cart status; it only reports whether the
    /// cart satisfies the current rules (min subtotal, max items, etc.).
    ///
    /// - Parameter cartID: Identifier of the cart to validate.
    /// - Returns: `CartValidationResult` describing whether the cart is valid
    ///            for checkout and, if not, why.
    /// - Throws: `CartError.conflict` if the cart cannot be loaded.
    public func validateBeforeCheckout(
        cartID: CartID
    ) async throws -> CartValidationResult {
        let cart = try await loadCartOrThrow(cartID)
        return await config.validationEngine.validate(cart: cart)
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

        let (cartToPersist, conflicts) = try await detectAndResolveCatalogConflictsIfNeeded(for: cart)
        let updatedCart = try await saveCartAfterMutation(cartToPersist)

        config.analyticsSink.itemAdded(item, in: updatedCart)

        return CartUpdateResult(
            cart: updatedCart,
            removedItems: [],
            changedItems: [item],
            conflicts: conflicts
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
            throw CartError.conflict(reason: "Item not found in cart")
        }

        try await validateItemChange(in: cart, item: updatedItem)

        cart.items[index] = updatedItem

        let (cartToPersist, conflicts) = try await detectAndResolveCatalogConflictsIfNeeded(for: cart)
        let updatedCart = try await saveCartAfterMutation(cartToPersist)

        config.analyticsSink.itemUpdated(updatedItem, in: updatedCart)

        return CartUpdateResult(
            cart: updatedCart,
            removedItems: [],
            changedItems: [updatedItem],
            conflicts: conflicts
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
            throw CartError.conflict(reason: "Item not found in cart")
        }

        let removedItem = cart.items.remove(at: index)

        let (cartToPersist, conflicts) = try await detectAndResolveCatalogConflictsIfNeeded(for: cart)
        let updatedCart = try await saveCartAfterMutation(cartToPersist)

        config.analyticsSink.itemRemoved(itemId: itemID, from: updatedCart)

        return CartUpdateResult(
            cart: updatedCart,
            removedItems: [removedItem],
            changedItems: [],
            conflicts: conflicts
        )
    }
    
    // MARK: - Helpers
    
    /// Loads a cart and enforces that it is present and mutable.
    ///
    /// Currently this means:
    /// - The cart exists in the underlying store.
    /// - The cart has `status == .active`.
    ///
    /// Non-existing or non-active carts result in a `CartError.conflict`
    /// so that callers know the operation cannot proceed on this cart.
    private func loadMutableCart(for id: CartID) async throws -> Cart {
        let cart = try await loadCartOrThrow(id)
        
        guard cart.status == .active else {
            throw CartError.conflict(reason: "Cart is not active")
        }
        
        return cart
    }
    
    /// Loads a cart for status changes without enforcing `status == .active`.
    ///
    /// Status transitions themselves are governed by
    /// `ensureValidStatusTransition(from:to:)`.
    private func loadCartForStatusChange(id: CartID) async throws -> Cart {
        let cart = try await loadCartOrThrow(id)
        return cart
    }
    
    /// Validates a proposed item change against the configured validation engine.
    ///
    /// This helper calls `CartValidationEngine.validateItemChange(in:proposedItem:)`
    /// and translates the resulting `CartValidationResult` into a `CartError`
    /// when the change is not allowed.
    ///
    /// - Parameters:
    ///   - cart: The current cart snapshot before applying the change.
    ///   - item: The item state we want to apply to the cart.
    /// - Throws: `CartError.validationFailed` when the validation engine
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
        case .invalid(let error):
            throw CartError.validationFailed(reason: error.message)
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
        
        throw CartError.conflict(reason: "Invalid cart status transition")
    }
    
    
    /// Clones cart items while regenerating their identities.
    ///
    /// Used during cart duplication/reorder to preserve item contents
    /// while avoiding identity coupling between the source and new cart.
    private func cloneItemsRegeneratingIDs(from items: [CartItem]) -> [CartItem] {
        items.map { item in
            CartItem(
                id: CartItemID.generate(),
                productID: item.productID,
                quantity: item.quantity,
                unitPrice: item.unitPrice,
                totalPrice: item.totalPrice,
                modifiers: item.modifiers,
                imageURL: item.imageURL,
                availableStock: item.availableStock
            )
        }
    }
    
    /// Creates a new active cart by copying the contents of an existing cart.
    ///
    /// Used by:
    /// - Reorder flows.
    /// - Guest → profile migration (copy strategy).
    ///
    /// The new cart:
    /// - Has a new `CartID`,
    /// - Regenerates all `CartItemID`s,
    /// - Resets timestamps,
    /// - Preserves cart-level metadata and configuration.
    private func makeActiveCartCopy(
        from source: Cart,
        profileID: UserProfileID?
    ) -> Cart {
        let now = Date()
        return Cart(
            id: CartID.generate(),
            storeID: source.storeID,
            profileID: profileID,
            items: cloneItemsRegeneratingIDs(from: source.items),
            status: .active,
            createdAt: now,
            updatedAt: now,
            metadata: source.metadata,
            displayName: source.displayName,
            context: source.context,
            storeImageURL: source.storeImageURL,
            minSubtotal: source.minSubtotal,
            maxItemCount: source.maxItemCount
        )
    }
    
    /// Persists a newly-created cart and emits creation analytics.
    ///
    /// Optionally emits `activeCartChanged` when the cart should become
    /// the active cart for its scope.
    @discardableResult
    private func persistNewCart(
        _ cart: Cart,
        setAsActive: Bool
    ) async throws -> Cart {
        try await config.cartStore.saveCart(cart)
        config.analyticsSink.cartCreated(cart)

        if setAsActive {
            config.analyticsSink.activeCartChanged(
                newActiveCartId: cart.id,
                storeId: cart.storeID,
                profileId: cart.profileID
            )
        }

        return cart
    }
    
    /// Expires the currently active cart for the given scope, if one exists.
    ///
    /// Used to enforce the invariant:
    /// - Only one active cart per `(storeID, profileID)` scope.
    private func expireActiveCartIfNeeded(
        storeID: StoreID,
        profileID: UserProfileID?
    ) async throws {
        if let active = try await getActiveCart(storeID: storeID, profileID: profileID) {
            var expired = active
            expired.status = .expired
            _ = try await saveCartAfterMutation(expired)
        }
    }
    
    /// Loads a cart by ID or throws a conflict error if it does not exist.
    ///
    /// Centralizes the \"cart not found\" error handling.
    private func loadCartOrThrow(_ id: CartID) async throws -> Cart {
        guard let cart = try await config.cartStore.loadCart(id: id) else {
            throw CartError.conflict(reason: "Cart not found")
        }
        return cart
    }
    
    /// Detects catalog conflicts for a proposed cart and optionally resolves them.
    ///
    /// - Returns:
    ///   - `cartToPersist`: the cart that should be persisted (original or resolved),
    ///   - `conflicts`: the detected catalog conflicts (always returned when present).
    private func detectAndResolveCatalogConflictsIfNeeded(
        for proposedCart: Cart
    ) async throws -> (cartToPersist: Cart, conflicts: [CartCatalogConflict]) {

        let conflicts = await config.catalogConflictDetector.detectConflicts(for: proposedCart)

        // No conflicts → persist as-is.
        guard !conflicts.isEmpty else {
            return (proposedCart, [])
        }

        // Conflicts, but no resolver configured → persist as-is and report conflicts.
        guard let resolver = config.conflictResolver else {
            return (proposedCart, conflicts)
        }

        // Conflicts + resolver → let client decide the policy.
        let reason = CartError.conflict(reason: "Cart has catalog conflicts")
        let resolution = await resolver.resolveConflict(for: proposedCart, reason: reason)

        switch resolution {
        case .acceptModifiedCart(let resolvedCart):
            return (resolvedCart, conflicts)

        case .rejectWithError(let error):
            throw error
        }
    }
}
