import Foundation
import Testing
import MultiCartCore
import MultiCartStorageCoreData

struct CoreDataCartStoreTests {
    
    // MARK: - Helpers
    
    private func makeSUT() async throws -> CartStore {
        // In-memory store for deterministic unit tests (no disk IO).
        let config = CoreDataCartStoreConfiguration(
            modelName: "CartStorage",
            inMemory: true
        )
        return try await CoreDataCartStore(configuration: config)
    }
    
    private func makeCart(
        id: CartID = .generate(),
        storeID: StoreID,
        profileID: UserProfileID?,
        status: CartStatus = .active,
        createdAt: Date = Date(timeIntervalSince1970: 1),
        updatedAt: Date = Date(timeIntervalSince1970: 2),
        metadata: [String: String] = ["source": "test"]
    ) -> Cart {
        Cart(
            id: id,
            storeID: storeID,
            profileID: profileID,
            items: [],
            status: status,
            createdAt: createdAt,
            updatedAt: updatedAt,
            metadata: metadata,
            displayName: "Test Cart",
            context: "unit-tests",
            storeImageURL: URL(string: "https://example.com/store.png"),
            minSubtotal: nil,
            maxItemCount: nil
        )
    }
    
    private func makeItem(
        id: CartItemID = CartItemID(rawValue: UUID().uuidString),
        productID: String = "p1",
        quantity: Int = 2,
        currency: String = "USD",
        unit: Decimal = 5
    ) -> CartItem {
        CartItem(
            id: id,
            productID: productID,
            quantity: quantity,
            unitPrice: Money(amount: unit, currencyCode: currency),
            totalPrice: Money(amount: unit * Decimal(quantity), currencyCode: currency),
            modifiers: [],
            imageURL: nil,
            availableStock: nil
        )
    }
    
    // MARK: - CRUD
    
    @Test
    func saveCart_thenLoadCart_returnsSameCart() async throws {
        let sut = try await makeSUT()
        
        let storeID = StoreID(rawValue: "store-1")
        let profileID = UserProfileID(rawValue: "profile-1")
        
        var cart = makeCart(storeID: storeID, profileID: profileID)
        cart.items = [makeItem(productID: "burger", quantity: 3)]
        
        try await sut.saveCart(cart)
        let loaded = try await sut.loadCart(id: cart.id)
        
        #expect(loaded != nil)
        #expect(loaded?.id == cart.id)
        #expect(loaded?.storeID == cart.storeID)
        #expect(loaded?.profileID == cart.profileID)
        #expect(loaded?.status == cart.status)
        #expect(loaded?.metadata == cart.metadata)
        #expect(loaded?.items.count == 1)
        #expect(loaded?.items.first?.productID == "burger")
        #expect(loaded?.items.first?.quantity == 3)
    }
    
    @Test
    func saveCart_whenSavingSameId_updatesExistingRecord() async throws {
        let sut = try await makeSUT()
        
        let storeID = StoreID(rawValue: "store-1")
        let profileID = UserProfileID(rawValue: "profile-1")
        
        let id = CartID.generate()
        
        var v1 = makeCart(
            id: id,
            storeID: storeID,
            profileID: profileID,
            status: .active,
            metadata: ["v": "1"]
        )
        v1.items = [makeItem(productID: "a", quantity: 1)]
        try await sut.saveCart(v1)
        
        var v2 = makeCart(
            id: id,
            storeID: storeID,
            profileID: profileID,
            status: .checkedOut,
            metadata: ["v": "2"]
        )
        v2.items = [makeItem(productID: "b", quantity: 4)]
        try await sut.saveCart(v2)
        
        let loaded = try await sut.loadCart(id: id)
        #expect(loaded?.metadata["v"] == "2")
        #expect(loaded?.status == .checkedOut)
        #expect(loaded?.items.count == 1)
        #expect(loaded?.items.first?.productID == "b")
        #expect(loaded?.items.first?.quantity == 4)
    }
    
    @Test
    func deleteCart_removesCart_andIsIdempotent() async throws {
        let sut = try await makeSUT()
        
        let storeID = StoreID(rawValue: "store-1")
        let cart = makeCart(storeID: storeID, profileID: nil)
        
        try await sut.saveCart(cart)
        #expect(try await sut.loadCart(id: cart.id) != nil)
        
        try await sut.deleteCart(id: cart.id)
        #expect(try await sut.loadCart(id: cart.id) == nil)
        
        // Idempotency: deleting again should not throw.
        try await sut.deleteCart(id: cart.id)
        #expect(try await sut.loadCart(id: cart.id) == nil)
    }
    
    // MARK: - Query semantics (guest vs logged-in)
    
    @Test
    func fetchCarts_filtersGuestVsLoggedInScopes() async throws {
        let sut = try await makeSUT()
        
        let storeA = StoreID(rawValue: "store-A")
        let storeB = StoreID(rawValue: "store-B")
        let profile1 = UserProfileID(rawValue: "profile-1")
        
        let guestA = makeCart(
            storeID: storeA,
            profileID: nil,
            status: .active,
            metadata: ["k": "guestA"]
        )
        
        let userA  = makeCart(
            storeID: storeA,
            profileID: profile1,
            status: .active,
            metadata: ["k": "userA"]
        )
        
        let guestB = makeCart(
            storeID: storeB,
            profileID: nil,
            status: .active,
            metadata: ["k": "guestB"]
        )
        
        try await sut.saveCart(guestA)
        try await sut.saveCart(userA)
        try await sut.saveCart(guestB)
        
        // Guest scope: storeA + profileID == nil
        let guestQuery = CartQuery(
            storeID: storeA,
            profileID: nil,
            statuses: nil,
            sort: .updatedAtDescending
        )
        let guestResults = try await sut.fetchCarts(matching: guestQuery, limit: nil)
        
        #expect(guestResults.count == 1)
        #expect(guestResults.first?.profileID == nil)
        #expect(guestResults.first?.storeID == storeA)
        #expect(guestResults.first?.metadata["k"] == "guestA")
        
        // Logged-in scope: storeA + profile1
        let userQuery = CartQuery(
            storeID: storeA,
            profileID: profile1,
            statuses: nil,
            sort: .updatedAtDescending
        )
        let userResults = try await sut.fetchCarts(matching: userQuery, limit: nil)
        
        #expect(userResults.count == 1)
        #expect(userResults.first?.profileID == profile1)
        #expect(userResults.first?.storeID == storeA)
        #expect(userResults.first?.metadata["k"] == "userA")
    }
    
    @Test
    func fetchCarts_filtersByStatusesWithinScope() async throws {
        let sut = try await makeSUT()
        
        let storeID = StoreID(rawValue: "store-A")
        let profileID = UserProfileID(rawValue: "profile-1")
        
        let active = makeCart(
            storeID: storeID,
            profileID: profileID,
            status: .active,
            metadata: ["s": "active"]
        )
        
        let checkedOut = makeCart(
            storeID: storeID,
            profileID: profileID,
            status: .checkedOut,
            metadata: ["s": "checkedOut"]
        )
        
        try await sut.saveCart(active)
        try await sut.saveCart(checkedOut)
        
        let q = CartQuery(
            storeID: storeID,
            profileID: profileID,
            statuses: [.active],
            sort: .updatedAtDescending
        )
        
        let results = try await sut.fetchCarts(matching: q, limit: nil)
        #expect(results.count == 1)
        #expect(results.first?.status == .active)
        #expect(results.first?.metadata["s"] == "active")
    }
    
    @Test
    func fetchCarts_respectsLimit() async throws {
        let sut = try await makeSUT()
        
        let storeID = StoreID(rawValue: "store-A")
        
        // Guest carts in same scope; limit should cap results.
        // (We vary IDs; updatedAt is fixed in helper, so count/limit is the main assertion.)
        try await sut.saveCart(
            makeCart(
                storeID: storeID,
                profileID: nil,
                metadata: ["i": "1"]
            )
        )
        
        try await sut.saveCart(
            makeCart(
                storeID: storeID,
                profileID: nil,
                metadata: ["i": "2"]
            )
        )
        
        try await sut.saveCart(
            makeCart(
                storeID: storeID,
                profileID: nil,
                metadata: ["i": "3"]
            )
        )
        
        let q = CartQuery(storeID: storeID, profileID: nil, statuses: nil, sort: .updatedAtDescending)
        let results = try await sut.fetchCarts(matching: q, limit: 2)
        
        #expect(results.count == 2)
    }
}
