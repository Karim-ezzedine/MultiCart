import Foundation
import Testing
@testable import MultiCartCore
import MultiCartTestingSupport

struct DefaultCartValidationEngineTests {
    
    private func cartWithSubtotal(_ amount: Decimal) -> Cart {
        let item = CartItem(
            id: CartItemID.generate(),
            productID: "item_1",
            quantity: 1,
            unitPrice: Money(amount: amount, currencyCode: "USD")
        )
        
        return Cart(
            id: CartID.generate(),
            storeID: CartTestFixtures.demoStoreID,
            profileID: nil,
            items: [item]
        )
    }
    
    @Test
    func validate_cartFailsWhenMinSubtotalNotMet() async throws {
        let minSubtotal = Money(amount: 20, currencyCode: "USD")
        let engine = DefaultCartValidationEngine(
            defaultMinSubtotal: minSubtotal,
            defaultMaxItems: nil
        )
        
        let cart = cartWithSubtotal(15)
        
        let result = await engine.validate(cart: cart)
        switch result {
        case .valid:
            Issue.record("Expected invalid result for minSubtotalNotMet")
        case .invalid(let error):
            if case let .minSubtotalNotMet(required, actual) = error {
                #expect(required.amount == 20)
                #expect(actual.amount == 15)
            } else {
                Issue.record("Expected minSubtotalNotMet, got \(error)")
            }
        }
    }
    
    @Test
    func validate_cartFailsWhenMaxItemsExceeded() async throws {
        let engine = DefaultCartValidationEngine(
            defaultMinSubtotal: nil,
            defaultMaxItems: 2
        )
        
        let item1 = CartItem(
            id: CartItemID.generate(),
            productID: "item_1",
            quantity: 1,
            unitPrice: Money(amount: 5, currencyCode: "USD")
        )
        let item2 = CartItem(
            id: CartItemID.generate(),
            productID: "item_2",
            quantity: 1,
            unitPrice: Money(amount: 5, currencyCode: "USD")
        )
        let item3 = CartItem(
            id: CartItemID.generate(),
            productID: "item_3",
            quantity: 1,
            unitPrice: Money(amount: 5, currencyCode: "USD")
        )
        
        let cart = Cart(
            id: CartID.generate(),
            storeID: CartTestFixtures.demoStoreID,
            profileID: nil,
            items: [item1, item2, item3]
        )
        
        let result = await engine.validate(cart: cart)
        switch result {
        case .valid:
            Issue.record("Expected invalid result for maxItemsExceeded")
        case .invalid(let error):
            if case let .maxItemsExceeded(max, actual) = error {
                #expect(max == 2)
                #expect(actual == 3)
            } else {
                Issue.record("Expected maxItemsExceeded, got \(error)")
            }
        }
    }
    
    @Test
    func validateItemChange_failsOnNonPositiveQuantity() async throws {
        let engine = DefaultCartValidationEngine()
        
        let cart = Cart(
            id: CartID.generate(),
            storeID: CartTestFixtures.demoStoreID,
            profileID: nil,
            items: []
        )
        
        let proposed = CartItem(
            id: CartItemID.generate(),
            productID: "item_1",
            quantity: 0,
            unitPrice: Money(amount: 5, currencyCode: "USD")
        )
        
        let result = await engine.validateItemChange(in: cart, proposedItem: proposed)
        switch result {
        case .valid:
            Issue.record("Expected invalid result for non-positive quantity")
        case .invalid(let error):
            if case .custom(let message) = error {
                #expect(message.contains("Quantity"))
            } else {
                Issue.record("Expected custom error, got \(error)")
            }
        }
    }
    
    @Test
    func validateItemChange_failsWhenQuantityExceedsAvailableStock() async throws {
        let engine = DefaultCartValidationEngine()
        
        let cart = Cart(
            id: CartID.generate(),
            storeID: CartTestFixtures.demoStoreID,
            profileID: nil,
            items: []
        )
        
        let proposed = CartItem(
            id: CartItemID.generate(),
            productID: "item_1",
            quantity: 10,
            unitPrice: Money(amount: 5, currencyCode: "USD"),
            availableStock: 5
        )
        
        let result = await engine.validateItemChange(in: cart, proposedItem: proposed)
        switch result {
        case .valid:
            Issue.record("Expected invalid result for quantityExceedsAvailableStock")
        case .invalid(let error):
            if case let .quantityExceedsAvailableStock(_, available, requested) = error {
                #expect(available == 5)
                #expect(requested == 10)
            } else {
                Issue.record("Expected quantityExceedsAvailableStock, got \(error)")
            }
        }
    }
}
