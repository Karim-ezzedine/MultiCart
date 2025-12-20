import Foundation
import CoreData
import MultiCartCore

/// `CartStore` adapter backed by Core Data.
///
/// Clean Architecture note:
/// - `CartStore` is a Core "port" (interface).
/// - `CoreDataCartStore` is the Infrastructure adapter that implements the port.
///
/// Concurrency note:
/// - All Core Data work is executed through `perform(_:)` on a dedicated background context.
extension CoreDataCartStore: CartStore {
    
    /// Loads a single cart by identifier.
    ///
    /// - Returns: A domain `Cart` if found; otherwise `nil`.
    /// - Throws: Propagates Core Data fetch errors or mapping errors.
    public func loadCart(id: CartID) async throws -> Cart? {
        try await perform { context in
            guard let cd = try CoreDataCartMapping.fetchCDCart(id: id, in: context) else {
                return nil
            }
            return try CoreDataCartMapping.toDomain(cd)
        }
    }
    
    /// Inserts or updates the provided domain cart.
    ///
    /// Implementation details:
    /// - `upsertCart` mutates managed objects in the given context (Core Data reference graph).
    /// - The returned `CDCart` is not needed here; persisting is done by saving the context.
    /// - Only calls `save()` when `context.hasChanges` is `true`.
    public func saveCart(_ cart: Cart) async throws {
        try await perform { context in
            _ = try CoreDataCartMapping.upsertCart(cart, in: context)
            
            if context.hasChanges {
                try context.save()
            }
        }
    }
    
    /// Deletes a cart by identifier.
    ///
    /// Idempotency:
    /// - If the cart does not exist, no error is thrown and no save occurs.
    public func deleteCart(id: CartID) async throws {
        try await perform { context in
            if let cd = try CoreDataCartMapping.fetchCDCart(id: id, in: context) {
                context.delete(cd)
            }
            
            if context.hasChanges {
                try context.save()
            }
        }
    }
    
    /// Fetches carts matching the given query.
    ///
    /// Supported filters:
    /// - store scope (`storeId`)
    /// - profile scope (`profileId`, including guest scope when `nil`)
    /// - optional status set (`status IN ...`)
    ///
    /// Sorting and limiting are applied at the Core Data request level.
    public func fetchCarts(matching query: CartQuery, limit: Int?) async throws -> [Cart] {
        try await perform { context in
            let request: NSFetchRequest<CDCart> = CDCart.fetchRequest()
            
            var predicates: [NSPredicate] = []
            
            // Scope: store
            predicates.append(NSPredicate(format: "storeId == %@", query.storeID.rawValue))
            
            // Scope: profile (guest vs logged-in)
            if let profileID = query.profileID {
                predicates.append(NSPredicate(format: "profileId == %@", profileID.rawValue))
            } else {
                predicates.append(NSPredicate(format: "profileId == nil"))
            }
            
            // Optional status filter
            if let statuses = query.statuses, !statuses.isEmpty {
                let raw = statuses.map { $0.rawValue }
                predicates.append(NSPredicate(format: "status IN %@", raw))
            }
            
            request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
            
            // Sorting
            request.sortDescriptors = Self.sortDescriptors(for: query.sort)
            
            // Limit
            if let limit {
                request.fetchLimit = max(0, limit)
            }
            
            let results = try context.fetch(request)
            return try results.map(CoreDataCartMapping.toDomain)
        }
    }
    
    /// Maps `CartQuery.Sort` to Core Data sort descriptors.
    private static func sortDescriptors(for sort: CartQuery.Sort) -> [NSSortDescriptor] {
        switch sort {
        case .createdAtAscending:
            return [NSSortDescriptor(key: "createdAt", ascending: true)]
        case .createdAtDescending:
            return [NSSortDescriptor(key: "createdAt", ascending: false)]
        case .updatedAtAscending:
            return [NSSortDescriptor(key: "updatedAt", ascending: true)]
        case .updatedAtDescending:
            return [NSSortDescriptor(key: "updatedAt", ascending: false)]
        }
    }
}
