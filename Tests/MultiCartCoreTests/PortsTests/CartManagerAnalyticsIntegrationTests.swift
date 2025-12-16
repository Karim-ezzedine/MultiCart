import Foundation
import Testing
@testable import MultiCartCore
import MultiCartTestingSupport

/// Simple spy analytics sink for testing CartManager integration.
///
/// Not thread-safe in a general sense, but fine for sequential test usage.
final class SpyCartAnalyticsSink: CartAnalyticsSink, @unchecked Sendable {
    
    private(set) var createdCarts: [Cart] = []
    private(set) var updatedCarts: [Cart] = []
    private(set) var deletedCartIDs: [CartID] = []
    private(set) var activeCartChanges: [(CartID?, StoreID, UserProfileID?)] = []
    
    private(set) var addedItems: [(CartItem, Cart)] = []
    private(set) var updatedItems: [(CartItem, Cart)] = []
    private(set) var removedItems: [(CartItemID, Cart)] = []
    
    func cartCreated(_ cart: Cart) {
        createdCarts.append(cart)
    }
    
    func cartUpdated(_ cart: Cart) {
        updatedCarts.append(cart)
    }
    
    func cartDeleted(id: CartID) {
        deletedCartIDs.append(id)
    }
    
    func activeCartChanged(
        newActiveCartId: CartID?,
        storeId: StoreID,
        profileId: UserProfileID?
    ) {
        activeCartChanges.append((newActiveCartId, storeId, profileId))
    }
    
    func itemAdded(_ item: CartItem, in cart: Cart) {
        addedItems.append((item, cart))
    }
    
    func itemUpdated(_ item: CartItem, in cart: Cart) {
        updatedItems.append((item, cart))
    }
    
    func itemRemoved(
        itemId: CartItemID,
        from cart: Cart
    ) {
        removedItems.append((itemId, cart))
    }
}

struct CartManagerAnalyticsIntegrationTests {
    
    private func makeManager(
        now: Date = Date()
    ) -> (CartManager, SpyCartAnalyticsSink) {
        let store = InMemoryCartStore(initialCarts: [])
        let analytics = SpyCartAnalyticsSink()
        
        let config = CartConfiguration(
            cartStore: store,
            analyticsSink: analytics
        )
        
        let manager = CartManager(configuration: config)
        return (manager, analytics)
    }
    
    @Test
    func createCart_andAddItem_emitAnalyticsEvents() async throws {
        let (manager, analytics) = makeManager()
        let storeID = CartTestFixtures.demoStoreID
        
        // Act: create active cart
        let cart = try await manager.setActiveCart(storeID: storeID, profileID: nil)
        
        // Manager internally calls createCart → cartCreated
        #expect(analytics.createdCarts.count == 1)
        #expect(analytics.createdCarts.first?.id == cart.id)
        
        // Act: add item
        let item = CartItem(
            id: CartItemID.generate(),
            productID: "item_1",
            quantity: 1,
            unitPrice: Money(amount: 10, currencyCode: "USD")
        )
        let updateResult = try await manager.addItem(to: cart.id, item: item)
        
        // Analytics: itemAdded + cartUpdated
        #expect(analytics.addedItems.count == 1)
        #expect(analytics.updatedCarts.count >= 1)
        
        let added = analytics.addedItems.first
        #expect(added?.0.id == item.id)
        #expect(added?.1.id == updateResult.cart.id)
    }
    
    @Test
    func deleteCart_emitsDeletedAndActiveCartChanged() async throws {
        let (manager, analytics) = makeManager()
        let storeID = CartTestFixtures.demoStoreID
        
        let cart = try await manager.setActiveCart(storeID: storeID, profileID: nil)
        #expect(analytics.createdCarts.count == 1)
        
        try await manager.deleteCart(id: cart.id)
        
        // cartDeleted
        #expect(analytics.deletedCartIDs.contains(cart.id))
        
        // activeCartChanged with nil newActiveCartId after deleting an active cart
        #expect(
            analytics.activeCartChanges.contains(where: { change in
                let (newActiveID, sID, pID) = change
                return newActiveID == nil && sID == cart.storeID && pID == cart.profileID
            })
        )
    }
    
    @Test
    func checkout_emitsCartUpdatedWithCheckedOutStatus() async throws {
        let (manager, analytics) = makeManager()
        let storeID = CartTestFixtures.demoStoreID
        
        let cart = try await manager.setActiveCart(storeID: storeID, profileID: UserProfileID(rawValue: "user_1"))
        
        // Add at least one item so validation passes by default.
        let item = CartItem(
            id: CartItemID.generate(),
            productID: "item_1",
            quantity: 1,
            unitPrice: Money(amount: 10, currencyCode: "USD")
        )
        _ = try await manager.addItem(to: cart.id, item: item)
        
        // Act: update status to checkedOut
        let checkedOut = try await manager.updateStatus(
            for: cart.id,
            to: .checkedOut
        )
        
        // Expect last updated cart to have checkedOut status
        let lastUpdated = analytics.updatedCarts.last
        #expect(lastUpdated?.id == checkedOut.id)
        #expect(lastUpdated?.status == .checkedOut)
    }
}
