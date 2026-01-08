import Foundation
import Testing
@testable import CartKitCore
import CartKitTestingSupport

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
    
    //MARK: - Get Cart Tests
    
    @Test
    func getCart_returnsCart_whenExists() async throws {
        let cart = CartTestFixtures.guestCart(storeID: StoreID(rawValue: "store_get"))
        let manager = makeManager(initialCarts: [cart])

        let loaded = try await manager.getCart(id: cart.id)

        let unwrapped = try #require(loaded)
        #expect(unwrapped.id == cart.id)
    }
    
    @Test
    func getCart_returnsNil_whenMissing() async throws {
        let manager = makeManager(initialCarts: [])
        let loaded = try await manager.getCart(id: CartID.generate())
        #expect(loaded == nil)
    }
    
    //MARK: - Reorder Tests
    
    @Test
    func reorder_throws_whenSourceCartMissing() async throws {
        let manager = makeManager()
        await #expect(throws: CartError.self) {
            _ = try await manager.reorder(from: CartID.generate())
        }
    }

    @Test
    func reorder_createsNewActiveCart_withNewIDs_andCopiedFields() async throws {
        let storeID = StoreID(rawValue: "store_reorder_core")
        let profileID: UserProfileID? = nil

        var source = CartTestFixtures.guestCart(storeID: storeID)

        source.displayName = "My Cart"
        source.context = "home"
        source.metadata = ["k": "v"]
        source.storeImageURL = URL(string: "https://example.com/s.png")
        source.minSubtotal = Money(amount: 10, currencyCode: "USD")
        source.maxItemCount = 7

        let manager = makeManager(initialCarts: [source])

        let reordered = try await manager.reorder(from: source.id)

        #expect(reordered.id != source.id)
        #expect(reordered.status == .active)
        #expect(reordered.storeID == storeID)
        #expect(reordered.profileID == profileID)

        #expect(reordered.displayName == source.displayName)
        #expect(reordered.context == source.context)
        #expect(reordered.metadata == source.metadata)
        #expect(reordered.storeImageURL == source.storeImageURL)
        #expect(reordered.minSubtotal == source.minSubtotal)
        #expect(reordered.maxItemCount == source.maxItemCount)
    }

    @Test
    func reorder_regeneratesCartItemIDs_butKeepsItemContent() async throws {
        let storeID = StoreID(rawValue: "store_reorder_items")
        var source = CartTestFixtures.guestCart(storeID: storeID)

        // Ensure at least one item exists; if fixture is empty, add one.
        if source.items.isEmpty {
            source.items = [
                CartItem(
                    id: CartItemID.generate(),
                    productID: "p1",
                    quantity: 2,
                    unitPrice: Money(amount: 5, currencyCode: "USD"),
                    modifiers: [CartItemModifier(id: "m1", name: "extra", priceDelta: Money(amount: 1, currencyCode: "USD"))],
                    imageURL: URL(string: "https://example.com/i.png"),
                    availableStock: 10
                )
            ]
        }

        let manager = makeManager(initialCarts: [source])
        let reordered = try await manager.reorder(from: source.id)

        #expect(reordered.items.count == source.items.count)

        let sourceByProduct = Dictionary(uniqueKeysWithValues: source.items.map { ($0.productID, $0) })
        for item in reordered.items {
            let original = try #require(sourceByProduct[item.productID])
            #expect(item.id != original.id)              // regenerated
            #expect(item.productID == original.productID)
            #expect(item.quantity == original.quantity)
            #expect(item.unitPrice == original.unitPrice)
            #expect(item.totalPrice == original.totalPrice)
            #expect(item.modifiers == original.modifiers)
            #expect(item.imageURL == original.imageURL)
            #expect(item.availableStock == original.availableStock)
        }
    }

    @Test
    func reorder_expiresExistingActiveCart_inSameScope() async throws {
        let storeID = StoreID(rawValue: "store_reorder_expire")

        // Existing active cart in scope
        var active = CartTestFixtures.guestCart(storeID: storeID)
        active.status = .active

        // Source cart (can also be active or non-active; reorder source is independent)
        var source = CartTestFixtures.guestCart(storeID: storeID)
        source.status = .expired

        let manager = makeManager(initialCarts: [active, source])

        let reordered = try await manager.reorder(from: source.id)

        #expect(reordered.status == .active)
        #expect(reordered.storeID == storeID)

        // Old active cart should now be expired
        let oldLoaded = try await manager.getCart(id: active.id)
        let old = try #require(oldLoaded)
        #expect(old.status == .expired)
    }

    @Test
    func reorder_doesNotExpireActiveCart_inDifferentScope() async throws {
        let storeA = StoreID(rawValue: "store_A")
        let storeB = StoreID(rawValue: "store_B")

        var activeA = CartTestFixtures.guestCart(storeID: storeA)
        activeA.status = .active

        let sourceB = CartTestFixtures.guestCart(storeID: storeB)

        let manager = makeManager(initialCarts: [activeA, sourceB])

        _ = try await manager.reorder(from: sourceB.id)

        let stillActiveA = try await manager.getCart(id: activeA.id)
        let a = try #require(stillActiveA)
        #expect(a.status == .active)   // untouched
    }
    
    //MARK: - Migrate from guest to logged in
    
    @Test
    func migrateGuestActiveCart_move_rescopesSameCart() async throws {
        let storeID = StoreID("store_move")
        let profileID = UserProfileID("profile_1")

        var guest = CartTestFixtures.guestCart(storeID: storeID)
        guest.status = .active

        let manager = makeManager(initialCarts: [guest])

        let migrated = try await manager.migrateGuestActiveCart(
            storeID: storeID,
            to: profileID,
            strategy: .move
        )

        #expect(migrated.id == guest.id)
        #expect(migrated.profileID == profileID)
        #expect(migrated.status == .active)

        // Guest scope should now be empty
        let guestActive = try await manager.getActiveCart(storeID: storeID, profileID: nil)
        #expect(guestActive == nil)
    }

    @Test
    func migrateGuestActiveCart_copyAndDelete_createsNewProfileCart_andDeletesGuest() async throws {
        let storeID = StoreID("store_copy")
        let profileID = UserProfileID("profile_2")

        var guest = CartTestFixtures.guestCart(storeID: storeID)
        guest.status = .active

        let manager = makeManager(initialCarts: [guest])

        let migrated = try await manager.migrateGuestActiveCart(
            storeID: storeID,
            to: profileID,
            strategy: .copyAndDelete
        )

        #expect(migrated.id != guest.id)
        #expect(migrated.profileID == profileID)
        #expect(migrated.status == .active)

        // Guest cart should be deleted
        let deletedGuest = try await manager.getCart(id: guest.id)
        #expect(deletedGuest == nil)

        // Items cloned with new IDs
        let srcByProduct = Dictionary(uniqueKeysWithValues: guest.items.map { ($0.productID, $0) })
        for item in migrated.items {
            let original = try #require(srcByProduct[item.productID])
            #expect(item.id != original.id)
            #expect(item.quantity == original.quantity)
        }
    }

    @Test
    func migrateGuestActiveCart_throwsConflict_whenProfileHasActiveCart() async throws {
        let storeID = StoreID("store_conflict")
        let profileID = UserProfileID("profile_conflict")

        var guest = CartTestFixtures.guestCart(storeID: storeID)
        guest.status = .active

        var profileCart = CartTestFixtures.loggedInCart(
            storeID: storeID,
            profileID: profileID
        )
        profileCart.status = .active

        let manager = makeManager(initialCarts: [guest, profileCart])

        await #expect(throws: CartError.self) {
            _ = try await manager.migrateGuestActiveCart(
                storeID: storeID,
                to: profileID,
                strategy: .move
            )
        }

        // Ensure nothing changed
        let stillGuest = try await manager.getCart(id: guest.id)
        #expect(stillGuest?.profileID == nil)

        let stillProfile = try await manager.getCart(id: profileCart.id)
        #expect(stillProfile?.status == .active)
    }
    
    @Test
    func migrateGuestActiveCart_throwsConflict_whenNoActiveGuestCart() async throws {
        let manager = makeManager()

        await #expect(throws: CartError.self) {
            _ = try await manager.migrateGuestActiveCart(
                storeID: StoreID("store_none"),
                to: UserProfileID("profile_none"),
                strategy: .move
            )
        }
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
        to cartTotals: CartKitCore.CartTotals
    ) async throws -> CartKitCore.CartTotals {
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
