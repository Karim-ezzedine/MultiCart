import Foundation

/// Simple default implementation:
/// - subtotal = sum(unitPrice * quantity)
/// - tax = subtotal * taxRate
/// - fees = serviceFee + deliveryFee
/// - grandTotal = subtotal + tax + fees - manualDiscount
public struct DefaultCartPricingEngine: CartPricingEngine, Sendable {
    
    public init() {}
    
    public func computeTotals(
        for cart: Cart,
        context: CartPricingContext
    ) async throws -> CartTotals {
        
        // Pick a currency (assume all line items share it).
        let currencyCode =
        cart.items.first?.unitPrice.currencyCode ??
        context.serviceFee?.currencyCode ??
        context.deliveryFee?.currencyCode ??
        context.manualDiscount?.currencyCode ?? "USD"
        
        // Subtotal of line items
        var subtotalAmount = Decimal(0)
        for item in cart.items {
            subtotalAmount += item.unitPrice.amount * Decimal(item.quantity)
        }
        let subtotal = Money(amount: subtotalAmount, currencyCode: currencyCode)
        
        // Tax
        let taxAmount = subtotal.amount * context.taxRate
        let tax = Money(amount: taxAmount, currencyCode: currencyCode)
        
        // Fees (service + delivery)
        let feesAmount =
        (context.serviceFee?.amount ?? 0) +
        (context.deliveryFee?.amount ?? 0)
        
        let fees = Money(amount: feesAmount, currencyCode: currencyCode)
        
        // Discount (cart-level)
        let discount = context.manualDiscount ?? Money(amount: 0, currencyCode: currencyCode)
        
        // Grand total
        let grandAmount =
        subtotal.amount +
        tax.amount +
        fees.amount -
        discount.amount
        
        let grandTotal = Money(amount: grandAmount, currencyCode: currencyCode)
        
        return CartTotals(
            subtotal: subtotal,
            discount: discount,
            grandTotal: grandTotal
        )
    }
}
