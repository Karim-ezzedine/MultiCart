import Foundation
import Testing
@testable import MultiCartCore
import MultiCartTestingSupport

struct CartManagerDomainTests {

    // MARK: - Factory

    private func makeManager(
        initialCarts: [Cart] = []
    ) -> CartManager {
        let store = InMemoryCartStore(initialCarts: initialCarts)

        let config = CartConfiguration(
            cartStore: store,
            conflictResolver: NoOpConflictResolver()
        )

        return CartManager(configuration: config)
    }

    // MARK: -  Add / Update / Remove

    @Test
    func addItem_appendsItem_andReportsChangedItems() async throws {
        let manager = makeManager()
        let storeID = StoreID(rawValue: "store_add")
        
        let cart = try await manager.setActiveCart(storeID: storeID)

        let newItem = CartItem(
            id: CartItemID.generate(),
            productID: "burger",
            quantity: 1,
            unitPrice: Money(amount: 10, currencyCode: "USD"),
            modifiers: [],
            imageURL: nil
        )

        let result = try await manager.addItem(to: cart.id, item: newItem)

        #expect(result.cart.id == cart.id)
        #expect(result.cart.items.count == 1)
        #expect(result.removedItems.isEmpty)
        #expect(result.changedItems.count == 1)
        #expect(result.changedItems.first?.id == newItem.id)
        #expect(result.cart.items.contains { $0.id == newItem.id })
    }

    @Test
    func updateItem_changesExistingItem_andReportsChange() async throws {
        let manager = makeManager()
        let storeID = StoreID(rawValue: "store_update")
        
        var cart = try await manager.setActiveCart(storeID: storeID)

        let originalItem = CartItem(
            id: CartItemID.generate(),
            productID: "pizza",
            quantity: 1,
            unitPrice: Money(amount: 12, currencyCode: "USD"),
            modifiers: [],
            imageURL: nil
        )

        let addResult = try await manager.addItem(to: cart.id, item: originalItem)
        cart = addResult.cart

        var updatedItem = originalItem
        updatedItem.quantity = 2

        let updateResult = try await manager.updateItem(in: cart.id, item: updatedItem)

        #expect(updateResult.cart.items.count == 1)
        #expect(updateResult.removedItems.isEmpty)
        #expect(updateResult.changedItems.count == 1)
        #expect(updateResult.changedItems.first?.id == originalItem.id)
        #expect(updateResult.cart.items.first?.quantity == 2)
    }

    @Test
    func removeItem_removesLine_andReportsRemovedItems() async throws {
        let manager = makeManager()
        let storeID = StoreID(rawValue: "store_remove")
        
        var cart = try await manager.setActiveCart(storeID: storeID)

        let item = CartItem(
            id: CartItemID.generate(),
            productID: "fries",
            quantity: 1,
            unitPrice: Money(amount: 3, currencyCode: "USD"),
            modifiers: [],
            imageURL: nil
        )

        let addResult = try await manager.addItem(to: cart.id, item: item)
        cart = addResult.cart

        let removeResult = try await manager.removeItem(from: cart.id, itemID: item.id)

        #expect(removeResult.cart.items.isEmpty)
        #expect(removeResult.removedItems.count == 1)
        #expect(removeResult.removedItems.first?.id == item.id)
        #expect(removeResult.changedItems.isEmpty)
    }

    // MARK: - Status transitions

    @Test
    func updateStatus_allowsActiveToCheckedOut() async throws {
        let manager = makeManager()
        let storeID = StoreID(rawValue: "store_status")
        let profileID = UserProfileID(rawValue: "user_1")

        let cart = try await manager.setActiveCart(storeID: storeID, profileID: profileID)

        let updated = try await manager.updateStatus(
            for: cart.id,
            to: .checkedOut
        )

        #expect(updated.status == .checkedOut)
    }

    @Test
    func updateStatus_disallowsCheckedOutBackToActive() async throws {
        let manager = makeManager()
        let storeID = StoreID(rawValue: "store_status_back")
        let profileID = UserProfileID(rawValue: "user_1")

        let cart = try await manager.setActiveCart(storeID: storeID, profileID: profileID)
        _ = try await manager.updateStatus(for: cart.id, to: .checkedOut)

        await #expect(throws: CartError.self) {
            _ = try await manager.updateStatus(for: cart.id, to: .active)
        }
    }

    // MARK: - Active cart per store/profile

    @Test
    func setActiveCart_reusesExistingActive_forSameScope() async throws {
        let manager = makeManager()
        let storeID = StoreID(rawValue: "store_scope")
        let profileID = UserProfileID(rawValue: "user_1")

        let first = try await manager.setActiveCart(storeID: storeID, profileID: profileID)
        let second = try await manager.setActiveCart(storeID: storeID, profileID: profileID)

        #expect(first.id == second.id)
    }

    @Test
    func activeCarts_areScopedByStoreID() async throws {
        let manager = makeManager()
        let profileID = UserProfileID(rawValue: "user_scope")

        let storeA = StoreID(rawValue: "store_A")
        let storeB = StoreID(rawValue: "store_B")

        let cartA = try await manager.setActiveCart(storeID: storeA, profileID: profileID)
        let cartB = try await manager.setActiveCart(storeID: storeB, profileID: profileID)

        let fetchedA = try await manager.getActiveCart(storeID: storeA, profileID: profileID)
        let fetchedB = try await manager.getActiveCart(storeID: storeB, profileID: profileID)

        #expect(cartA.id != cartB.id)
        #expect(fetchedA?.id == cartA.id)
        #expect(fetchedB?.id == cartB.id)
    }

    @Test
    func guestAndProfileCarts_areDistinctScopes() async throws {
        let manager = makeManager()
        let storeID = StoreID(rawValue: "store_guest_profile")
        let profileID = UserProfileID(rawValue: "user_42")

        let guestCart = try await manager.setActiveCart(storeID: storeID)
        let profileCart = try await manager.setActiveCart(storeID: storeID, profileID: profileID)

        let fetchedGuest = try await manager.getActiveCart(storeID: storeID)
        let fetchedProfile = try await manager.getActiveCart(storeID: storeID, profileID: profileID)

        #expect(guestCart.id != profileCart.id)
        #expect(fetchedGuest?.id == guestCart.id)
        #expect(fetchedProfile?.id == profileCart.id)
    }
}

// MARK: - Test doubles

private struct NoOpPricingEngine: CartPricingEngine, Sendable {
    func computeTotals(
        for cart: Cart,
        context: CartPricingContext
    ) async throws -> CartTotals {
        CartTotals(
            subtotal: Money(amount: 0, currencyCode: "USD"),
            grandTotal: Money(amount: 0, currencyCode: "USD")
        )
    }
}

private struct NoOpPromotionEngine: PromotionEngine, Sendable {
    func applyPromotions(
        _ promotions: [PromotionKind],
        to cartTotals: MultiCartCore.CartTotals
    ) async throws -> MultiCartCore.CartTotals {
        return cartTotals
    }
}

private struct AllowAllValidationEngine: CartValidationEngine, Sendable {
    func validate(cart: Cart) async -> CartValidationResult {
        .valid
    }
    
    func validateItemChange(
        in cart: Cart,
        proposedItem: CartItem
    ) async -> CartValidationResult {
        .valid
    }
}

private struct NoOpConflictResolver: CartConflictResolver, Sendable {
    func resolveConflict(for cart: Cart, reason: CartError) async -> CartConflictResolution {
        .acceptModifiedCart(cart)
    }
}

private struct NoOpAnalyticsSink: CartAnalyticsSink, Sendable {
    func cartCreated(_ cart: Cart) {}
    func cartUpdated(_ cart: Cart) {}
    func cartDeleted(id: CartID) {}
    func activeCartChanged(
        newActiveCartId: CartID?,
        storeId: StoreID,
        profileId: UserProfileID?
    ) {}
    func itemAdded(_ item: CartItem, in cart: Cart) {}
    func itemUpdated(_ item: CartItem, in cart: Cart) {}
    func itemRemoved(itemId: CartItemID, from cart: Cart) {}
}
