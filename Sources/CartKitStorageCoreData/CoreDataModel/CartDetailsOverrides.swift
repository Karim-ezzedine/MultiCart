//
//  CartDetailsOverrides.swift
//  CartKit
//
//  Created by Karim Ezzeddine on 08/01/2026.
//


// MARK: - M6.1 Duplication / Templates / Reorder

public struct CartDetailsOverrides: Sendable {
    public var displayName: String?
    public var context: String?
    public var metadata: [String: String]?
    public var storeImageURL: URL?
    public var minSubtotal: Money?
    public var maxItemCount: Int?

    public init(
        displayName: String? = nil,
        context: String? = nil,
        metadata: [String: String]? = nil,
        storeImageURL: URL? = nil,
        minSubtotal: Money? = nil,
        maxItemCount: Int? = nil
    ) {
        self.displayName = displayName
        self.context = context
        self.metadata = metadata
        self.storeImageURL = storeImageURL
        self.minSubtotal = minSubtotal
        self.maxItemCount = maxItemCount
    }
}

/// Simple read helper (keeps consumers talking to the facade).
public func getCart(id: CartID) async throws -> Cart? {
    try await config.cartStore.loadCart(id: id)
}

/// Duplicates an existing cart into a new cart.
///
/// - asTemplate:\n  - true  => stored non-active cart with template marker\n  - false => active cart copy (does not automatically become active for scope unless used via `reorder`)\npublic func duplicateCart(
    sourceCartID: CartID,
    overrides: CartDetailsOverrides? = nil,
    asTemplate: Bool = false
) async throws -> Cart {
    guard let source = try await config.cartStore.loadCart(id: sourceCartID) else {
        throw CartError.conflict(reason: "Cart not found")
    }

    // Build cloned cart snapshot
    let now = Date()
    let status: CartStatus = asTemplate ? .expired : .active

    var metadata = overrides?.metadata ?? source.metadata
    if asTemplate {
        metadata["multicart.template"] = "true"
    }

    let newCart = Cart(
        id: CartID.generate(),
        storeID: source.storeID,
        profileID: source.profileID,
        items: cloneItemsRegeneratingIDs(from: source.items),
        status: status,
        createdAt: now,
        updatedAt: now,
        metadata: metadata,
        displayName: overrides?.displayName ?? source.displayName,
        context: overrides?.context ?? source.context,
        storeImageURL: overrides?.storeImageURL ?? source.storeImageURL,
        minSubtotal: overrides?.minSubtotal ?? source.minSubtotal,
        maxItemCount: overrides?.maxItemCount ?? source.maxItemCount
    )

    try await config.cartStore.saveCart(newCart)
    config.analyticsSink.cartCreated(newCart)

    return newCart
}

/// Reorder flow:
/// - creates a new active cart copy from a source cart\n/// - expires any existing active cart in that scope\n/// - emits activeCartChanged to the new cart\npublic func reorder(from sourceCartID: CartID) async throws -> Cart {
    guard let source = try await config.cartStore.loadCart(id: sourceCartID) else {
        throw CartError.conflict(reason: "Cart not found")
    }

    // Expire any existing active cart in that scope (including the source if active)
    if let existingActive = try await getActiveCart(storeID: source.storeID, profileID: source.profileID) {
        if existingActive.status == .active {
            var expired = existingActive
            expired.status = .expired
            _ = try await saveCartAfterMutation(expired)
        }
    }

    let newCart = try await duplicateCart(
        sourceCartID: sourceCartID,
        overrides: nil,
        asTemplate: false
    )

    config.analyticsSink.activeCartChanged(
        newActiveCartId: newCart.id,
        storeId: newCart.storeID,
        profileId: newCart.profileID
    )

    return newCart
}
