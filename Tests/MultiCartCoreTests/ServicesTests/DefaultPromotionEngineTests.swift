import Foundation
import Testing
@testable import MultiCartCore

struct DefaultPromotionEngineTests {
    
    // MARK: - Helpers
    
    private func money(_ amount: Decimal) -> Money {
        Money(amount: amount, currencyCode: "USD")
    }
    
    private func baseTotals() -> CartTotals {
        CartTotals(
            subtotal: money(100), // base goods price
            deliveryFee: money(10),
            serviceFee: money(5),
            tax: money(0),
            grandTotal: money(115) // 100 + 10 + 5
        )
    }
    
    // MARK: - Tests
    
    @Test
    func applyPromotions_withNoPromotions_returnsUnchangedTotals() async throws {
        let engine = DefaultPromotionEngine()
        let totals = baseTotals()
        
        let result = try await engine.applyPromotions([], to: totals)
        
        #expect(result.subtotal == totals.subtotal)
        #expect(result.deliveryFee == totals.deliveryFee)
        #expect(result.serviceFee == totals.serviceFee)
        #expect(result.tax == totals.tax)
        #expect(result.grandTotal == totals.grandTotal)
    }
    
    @Test
    func applyPromotions_withFreeDelivery_setsDeliveryFeeToZeroAndRecomputesGrandTotal() async throws {
        let engine = DefaultPromotionEngine()
        let totals = baseTotals()
        
        let promotions: [PromotionKind] = [
            .freeDelivery
        ]
        
        let result = try await engine.applyPromotions(promotions, to: totals)
        
        #expect(result.deliveryFee.amount == 0)
        // grand = subtotal (100) + service (5) + tax (0) + delivery (0) = 105
        #expect(result.grandTotal.amount == 105)
    }
    
    @Test
    func applyPromotions_withSinglePercentageOff_appliesDiscountOnSubtotal() async throws {
        let engine = DefaultPromotionEngine()
        let totals = baseTotals()
        
        let promotions: [PromotionKind] = [
            .percentageOffCart(0.10)   // 10% off
        ]
        
        let result = try await engine.applyPromotions(promotions, to: totals)
        
        // subtotal: 100 - 10% = 90
        #expect(result.subtotal.amount == 90)
        // grand = 90 + 10 + 5 + 0 = 105
        #expect(result.grandTotal.amount == 105)
    }
    
    @Test
    func applyPromotions_withMultiplePercentages_aggregatesPercentages() async throws {
        let engine = DefaultPromotionEngine()
        let totals = baseTotals()
        
        let promotions: [PromotionKind] = [
            .percentageOffCart(0.10),  // 10%
            .percentageOffCart(0.05)   // 5% → total 15%
        ]
        
        let result = try await engine.applyPromotions(promotions, to: totals)
        
        // subtotal: 100 - 15% = 85
        #expect(result.subtotal.amount == 85)
        // grand = 85 + 10 + 5 + 0 = 100
        #expect(result.grandTotal.amount == 100)
    }
    
    @Test
    func applyPromotions_withFixedAmounts_aggregatesAndClampsSubtotal() async throws {
        let engine = DefaultPromotionEngine()
        let totals = baseTotals()
        
        let promotions: [PromotionKind] = [
            .fixedAmountOffCart(money(15)),
            .fixedAmountOffCart(money(10))
        ]
        
        let result = try await engine.applyPromotions(promotions, to: totals)
        
        // subtotal: 100 - (15 + 10) = 75
        #expect(result.subtotal.amount == 75)
        // grand = 75 + 10 + 5 + 0 = 90
        #expect(result.grandTotal.amount == 90)
    }
    
    @Test
    func applyPromotions_ignoresNegativeFixedDiscounts() async throws {
        let engine = DefaultPromotionEngine()
        let totals = baseTotals()
        
        let promotions: [PromotionKind] = [
            .fixedAmountOffCart(money(-20)), // should be ignored
            .fixedAmountOffCart(money(10)) // only this applies
        ]
        
        let result = try await engine.applyPromotions(promotions, to: totals)
        
        // subtotal: 100 - 10 = 90
        #expect(result.subtotal.amount == 90)
        // grand = 90 + 10 + 5 + 0 = 105
        #expect(result.grandTotal.amount == 105)
    }
    
    @Test
    func applyPromotions_withCombinationOfPercentageFixedAndFreeDelivery_appliesAllRules() async throws {
        let engine = DefaultPromotionEngine()
        let totals = baseTotals()
        
        let promotions: [PromotionKind] = [
            .freeDelivery,
            .percentageOffCart(0.10), // 10% off
            .fixedAmountOffCart(money(5)), // extra 5 off
            .custom(kind: "ignored-for-now", value: 10) // should have no effect
        ]
        
        let result = try await engine.applyPromotions(promotions, to: totals)
        
        // Start: subtotal 100
        // 10% off: 90
        // 5 fixed off: 85
        #expect(result.subtotal.amount == 85)
        
        // delivery = 0 because of freeDelivery
        #expect(result.deliveryFee.amount == 0)
        
        // service = 5, tax = 0
        #expect(result.serviceFee.amount == 5)
        #expect(result.tax.amount == 0)
        
        // grand = 85 + 0 + 5 + 0 = 90
        #expect(result.grandTotal.amount == 90)
    }
    
    @Test
    func applyPromotions_doesNotDropBelowZeroSubtotal() async throws {
        let engine = DefaultPromotionEngine()
        
        let smallTotals = CartTotals(
            subtotal: money(10),
            deliveryFee: money(0),
            serviceFee: money(0),
            tax: money(0),
            grandTotal: money(10)
        )
        
        let promotions: [PromotionKind] = [
            .fixedAmountOffCart(money(50)) // larger than subtotal
        ]
        
        let result = try await engine.applyPromotions(promotions, to: smallTotals)
        
        // clamped ≥ 0
        #expect(result.subtotal.amount == 0)
        #expect(result.grandTotal.amount == 0)
    }
}
