/// A conflict between a cart line and the current catalog state.
public struct CartCatalogConflict: Sendable, Equatable {
    public let itemID: CartItemID
    public let productID: String
    public let kind: Kind

    public init(itemID: CartItemID, productID: String, kind: Kind) {
        self.itemID = itemID
        self.productID = productID
        self.kind = kind
    }

    public enum Kind: Sendable, Equatable {
        /// The product no longer exists or is no longer orderable.
        case removedFromCatalog

        /// The catalog price differs from the cart line price.
        case priceChanged(old: Money, new: Money)

        /// The requested quantity exceeds the available stock.
        case insufficientStock(requested: Int, available: Int)
    }
}
