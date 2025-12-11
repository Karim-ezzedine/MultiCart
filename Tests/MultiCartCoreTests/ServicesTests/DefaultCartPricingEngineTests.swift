import Testing
@testable import MultiCartCore
import MultiCartTestingSupport

struct DefaultCartPricingEngineTests {
    
    @Test
    func computeTotals_withTaxAndFees_producesExpectedTotals() async throws {
        // Arrange
        let engine = DefaultCartPricingEngine()
        
        let item1 = CartItem(
            id: CartItemID.generate(),
            productID: "burger",
            quantity: 2,
            unitPrice: Money(amount: 10, currencyCode: "USD")
        )
        let item2 = CartItem(
            id: CartItemID.generate(),
            productID: "fries",
            quantity: 1,
            unitPrice: Money(amount: 5, currencyCode: "USD")
        )
        
        let cart = Cart(
            id: CartID.generate(),
            storeID: CartTestFixtures.demoStoreID,
            profileID: nil,
            items: [item1, item2]
        )
        
        let serviceFee = Money(amount: 1, currencyCode: "USD")
        let deliveryFee = Money(amount: 2, currencyCode: "USD")
        
        let context = CartPricingContext(
            storeID: cart.storeID,
            profileID: cart.profileID,
            serviceFee: serviceFee,
            deliveryFee: deliveryFee,
            taxRate: 0.10
        )
        
        // Act
        let totals = try await engine.computeTotals(for: cart, context: context)
        
        // Assert
        // Subtotal = 2 * 10 + 1 * 5 = 25
        #expect(totals.subtotal.amount == 25)
        #expect(totals.subtotal.currencyCode == "USD")
        
        // Tax = 25 * 0.10 = 2.5
        #expect(totals.tax.amount == 2.5)
        
        // Service + delivery stay as provided
        #expect(totals.serviceFee == serviceFee)
        #expect(totals.deliveryFee == deliveryFee)
        
        // Grand total = 25 + 2.5 + 1 + 2 = 30.5
        #expect(totals.grandTotal.amount == 30.5)
    }
}
