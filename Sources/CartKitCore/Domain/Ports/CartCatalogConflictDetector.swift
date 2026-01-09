/// Detects conflicts between a cart and the current catalog state.
///
/// This is a domain port:
/// - Implemented by the host app (or a catalog module),
/// - Used by `CartManager` to detect removed products, price changes, stock issues.
public protocol CartCatalogConflictDetector: Sendable {
    func detectConflicts(for cart: Cart) async -> [CartCatalogConflict]
}

/// Default implementation that reports no conflicts.
public struct NoOpCartCatalogConflictDetector: CartCatalogConflictDetector, Sendable {
    public init() {}
    public func detectConflicts(for cart: Cart) async -> [CartCatalogConflict] { [] }
}
