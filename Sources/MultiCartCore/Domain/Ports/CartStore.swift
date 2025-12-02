/// Parameters used to fetch carts from a CartStore.
///
/// Semantics:
/// - `storeID` is always required.
/// - `profileID == nil` means "guest carts for this store".
/// - `profileID != nil` means "carts for that profile in this store".
/// - `statuses == nil` means "any status".
/// - `statuses != nil` filters by the given statuses.
/// - `sort` controls ordering of the returned array.
public struct CartQuery: Hashable, Codable, Sendable {
    
    public enum Sort: String, Hashable, Codable, Sendable {
        /// Oldest carts first (by createdAt)
        case createdAtAscending
        
        /// Newest carts first (by createdAt)/
        case createdAtDescending
        
        /// Least recently updated first/
        case updatedAtAscending
        
        /// Most recently updated first (default)
        case updatedAtDescending
    }
    
    public let storeID: StoreID
    public let profileID: UserProfileID?
    public let statuses: Set<CartStatus>?
    public let sort: Sort
    
    public init(
        storeID: StoreID,
        profileID: UserProfileID? = nil,
        statuses: Set<CartStatus>? = nil,
        sort: Sort = .updatedAtDescending
    ) {
        self.storeID = storeID
        self.profileID = profileID
        self.statuses = statuses
        self.sort = sort
    }
    
    /// Convenience for querying active carts only.
    public static func active(
        storeID: StoreID,
        profileID: UserProfileID?
    ) -> CartQuery {
        CartQuery(
            storeID: storeID,
            profileID: profileID,
            statuses: [.active],
            sort: .updatedAtDescending
        )
    }
}

/// Abstraction over the underlying cart storage.
///
/// Implementations live in separate modules:
/// - MultiCartStorageCoreData
/// - MultiCartStorageSwiftData
///
/// This protocol is designed as a "port" in a hexagonal / clean architecture:
/// core logic (CartManager, engines) depends on this interface, not on the
/// concrete persistence technology.
public protocol CartStore: Sendable {
    
    /// Loads a single cart by its identifier.
    ///
    /// - Returns: `Cart` if found, otherwise `nil`.
    func loadCart(id: CartID) async throws -> Cart?
    
    /// Persists the given cart (insert or update).
    ///
    /// Implementations should ensure that `updatedAt` is stored as provided by
    /// the caller; the core will be responsible for bumping timestamps.
    func saveCart(_ cart: Cart) async throws
    
    /// Deletes a cart by its identifier.
    ///
    /// Implementations should be idempotent: deleting a missing cart should not throw.
    func deleteCart(id: CartID) async throws
    
    /// Fetches carts matching the given query.
    ///
    /// - Parameters:
    ///   - query: Scope + status filters + ordering.
    ///   - limit: Optional maximum number of carts to return. `nil` = no limit.
    func fetchCarts(
        matching query: CartQuery,
        limit: Int?
    ) async throws -> [Cart]
}
