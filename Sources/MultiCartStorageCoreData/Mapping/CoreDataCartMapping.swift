import Foundation
import CoreData
import MultiCartCore

/// Mapping utilities between Core Data entities (Infrastructure) and domain models (MultiCartCore).
///
/// DDD/Clean Architecture note:
/// - `CD*` entities are persistence DTOs (Infrastructure).
/// - `Cart`, `CartItem`, `CartItemModifier`, `Money` are domain models/value objects (Core).
/// - This type is the explicit mapping boundary between Core and Infrastructure.
enum CoreDataCartMapping {
    
    // MARK: - Domain -> Core Data
    
    /// Creates or updates a `CDCart` (and its child graph) from a domain `Cart`.
    ///
    /// Implementation details:
    /// - Uses `fetchCDCart` to locate an existing record; otherwise inserts a new `CDCart`.
    /// - Updates scalar fields, then replaces the full items/modifiers graph for determinism.
    /// - Persists optional domain values using conventions required by Core Data codegen
    ///   (e.g. some numeric optionals may be generated as non-optional scalars).
    ///
    /// - Returns: The managed object instance inside the provided `context` (reference type).
    static func upsertCart(
        _ cart: Cart,
        in context: NSManagedObjectContext
    ) throws -> CDCart {
        let cdCart = try fetchCDCart(id: cart.id, in: context) ?? CDCart(context: context)
        
        // Identifiers / scope
        cdCart.id = cart.id.rawValue
        cdCart.storeId = cart.storeID.rawValue
        cdCart.profileId = cart.profileID?.rawValue
        
        // State
        cdCart.status = cart.status.rawValue
        cdCart.createdAt = cart.createdAt
        cdCart.updatedAt = cart.updatedAt
        
        // Optional presentation metadata
        cdCart.displayName = cart.displayName
        cdCart.context = cart.context
        cdCart.storeImageURL = cart.storeImageURL?.absoluteString
        
        // Arbitrary metadata (stored as JSON Data)
        cdCart.metadataJSON = try encode(cart.metadata)
        
        // Store rule snapshots
        if let min = cart.minSubtotal {
            cdCart.minSubtotalAmount = NSDecimalNumber(decimal: min.amount)
            cdCart.minSubtotalCurrencyCode = min.currencyCode
        } else {
            cdCart.minSubtotalAmount = nil
            cdCart.minSubtotalCurrencyCode = nil
        }
        
        // Note:
        // If Core Data codegen produces a non-optional scalar (e.g. Int32),
        // we store `nil` as 0 and interpret 0 as `nil` on read.
        cdCart.maxItemCount = Int32(cart.maxItemCount ?? 0)
        
        // Replace items graph (simple + deterministic for v1).
        // This avoids complex diffing logic and ensures relationships match the domain snapshot.
        if let existingItems = cdCart.items as? Set<CDCartItem> {
            existingItems.forEach { context.delete($0) }
        }
        
        for item in cart.items {
            let cdItem = CDCartItem(context: context)
            apply(item, to: cdItem, in: context)
            cdItem.cart = cdCart
            cdCart.addToItems(cdItem)
        }
        
        return cdCart
    }
    
    /// Applies a domain `CartItem` onto an existing `CDCartItem`.
    ///
    /// - Important: This mutates a managed object owned by `context`.
    private static func apply(
        _ item: CartItem,
        to cdItem: CDCartItem,
        in context: NSManagedObjectContext
    ) {
        cdItem.id = item.id.rawValue
        cdItem.productId = item.productID
        cdItem.quantity = Int32(item.quantity)
        
        // Note:
        // If Core Data codegen uses a non-optional scalar, store `nil` as 0.
        cdItem.availableStock = Int32(item.availableStock ?? 0)
        
        cdItem.imageURL = item.imageURL?.absoluteString
        
        // Money flattening: persist as (amount + currencyCode).
        cdItem.unitPriceAmount = NSDecimalNumber(decimal: item.unitPrice.amount)
        cdItem.unitPriceCurrencyCode = item.unitPrice.currencyCode
        
        cdItem.totalPriceAmount = NSDecimalNumber(decimal: item.totalPrice.amount)
        cdItem.totalPriceCurrencyCode = item.totalPrice.currencyCode
        
        // Replace modifiers graph
        if let existingMods = cdItem.modifiers as? Set<CDCartItemModifier> {
            existingMods.forEach { context.delete($0) }
        }
        
        for mod in item.modifiers {
            let cdMod = CDCartItemModifier(context: context)
            cdMod.id = mod.id
            cdMod.name = mod.name
            cdMod.priceDeltaAmount = NSDecimalNumber(decimal: mod.priceDelta.amount)
            cdMod.priceDeltaCurrencyCode = mod.priceDelta.currencyCode
            cdMod.item = cdItem
            
            cdItem.addToModifiers(cdMod)
        }
    }
    
    // MARK: - Core Data -> Domain
    
    /// Converts a persisted `CDCart` graph into a domain `Cart`.
    ///
    /// - Throws: `CoreDataCartStoreError.dataCorrupted` when required fields are missing
    ///   or when stored values cannot be interpreted as valid domain values.
    static func toDomain(_ cdCart: CDCart) throws -> Cart {
        guard let id = cdCart.id,
              let storeId = cdCart.storeId,
              let statusRaw = cdCart.status,
              let createdAt = cdCart.createdAt,
              let updatedAt = cdCart.updatedAt
        else {
            throw CoreDataCartStoreError.dataCorrupted(entity: "CDCart")
        }
        
        guard let status = CartStatus(rawValue: statusRaw) else {
            throw CoreDataCartStoreError.dataCorrupted(entity: "CDCart.status")
        }
        
        let profileID: UserProfileID? = cdCart.profileId.map(UserProfileID.init(rawValue:))
        let metadata: [String: String] = try decode(cdCart.metadataJSON) ?? [:]
        let storeImageURL = cdCart.storeImageURL.flatMap(URL.init(string:))
        
        let minSubtotal: Money?
        if let amount = cdCart.minSubtotalAmount?.decimalValue,
           let currency = cdCart.minSubtotalCurrencyCode {
            minSubtotal = Money(amount: amount, currencyCode: currency)
        } else {
            minSubtotal = nil
        }
        
        // Convention: 0 => nil (for non-optional scalar codegen).
        let maxItemCount: Int? = (cdCart.maxItemCount > 0) ? Int(cdCart.maxItemCount) : nil
        
        let items: [CartItem] = try (cdCart.items as? Set<CDCartItem> ?? [])
            .map(toDomain)
            .sorted { $0.id.rawValue < $1.id.rawValue }
        
        return Cart(
            id: CartID(rawValue: id),
            storeID: StoreID(rawValue: storeId),
            profileID: profileID,
            items: items,
            status: status,
            createdAt: createdAt,
            updatedAt: updatedAt,
            metadata: metadata,
            displayName: cdCart.displayName,
            context: cdCart.context,
            storeImageURL: storeImageURL,
            minSubtotal: minSubtotal,
            maxItemCount: maxItemCount
        )
    }
    
    /// Converts a persisted `CDCartItem` (and modifiers) into a domain `CartItem`.
    ///
    /// - Throws: `CoreDataCartStoreError.dataCorrupted` when required fields are missing.
    private static func toDomain(_ cdItem: CDCartItem) throws -> CartItem {
        guard let id = cdItem.id,
              let productId = cdItem.productId,
              let unitPriceCurrency = cdItem.unitPriceCurrencyCode,
              let unitPriceAmount = cdItem.unitPriceAmount?.decimalValue
        else {
            throw CoreDataCartStoreError.dataCorrupted(entity: "CDCartItem")
        }
        
        let unitPrice = Money(amount: unitPriceAmount, currencyCode: unitPriceCurrency)
        
        let totalPrice: Money
        if let totalAmount = cdItem.totalPriceAmount?.decimalValue,
           let totalCurrency = cdItem.totalPriceCurrencyCode {
            totalPrice = Money(amount: totalAmount, currencyCode: totalCurrency)
        } else {
            // Fallback: compute total = unitPrice * quantity if missing in persistence.
            totalPrice = Money(
                amount: unitPrice.amount * Decimal(Int(cdItem.quantity)),
                currencyCode: unitPrice.currencyCode
            )
        }
        
        let modifiers: [CartItemModifier] = try (cdItem.modifiers as? Set<CDCartItemModifier> ?? [])
            .map { cdMod in
                guard let modId = cdMod.id,
                      let name = cdMod.name,
                      let deltaAmount = cdMod.priceDeltaAmount?.decimalValue,
                      let deltaCurrency = cdMod.priceDeltaCurrencyCode
                else {
                    throw CoreDataCartStoreError.dataCorrupted(entity: "CDCartItemModifier")
                }
                return CartItemModifier(
                    id: modId,
                    name: name,
                    priceDelta: Money(amount: deltaAmount, currencyCode: deltaCurrency)
                )
            }
            .sorted { $0.id < $1.id }
        
        let imageURL = cdItem.imageURL.flatMap(URL.init(string:))
        
        // Convention: 0 => nil (for non-optional scalar codegen).
        let availableStock: Int? = (cdItem.availableStock > 0) ? Int(cdItem.availableStock) : nil
        
        return CartItem(
            id: CartItemID(rawValue: id),
            productID: productId,
            quantity: Int(cdItem.quantity),
            unitPrice: unitPrice,
            totalPrice: totalPrice,
            modifiers: modifiers,
            imageURL: imageURL,
            availableStock: availableStock
        )
    }
    
    // MARK: - Fetch helpers
    
    /// Fetches a `CDCart` by id in the provided context.
    ///
    /// - Returns: The managed object if found, otherwise `nil`.
    static func fetchCDCart(id: CartID, in context: NSManagedObjectContext) throws -> CDCart? {
        let request: NSFetchRequest<CDCart> = CDCart.fetchRequest()
        request.fetchLimit = 1
        request.predicate = NSPredicate(format: "id == %@", id.rawValue)
        return try context.fetch(request).first
    }
    
    // MARK: - JSON helpers
    
    /// Encodes a dictionary into JSON `Data` for persistence.
    private static func encode(_ dict: [String: String]) throws -> Data {
        try JSONEncoder().encode(dict)
    }
    
    /// Decodes JSON `Data` into a dictionary.
    private static func decode(_ data: Data?) throws -> [String: String]? {
        guard let data else { return nil }
        return try JSONDecoder().decode([String: String].self, from: data)
    }
}
