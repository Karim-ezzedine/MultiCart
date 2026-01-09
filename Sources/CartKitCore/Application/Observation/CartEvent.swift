/// Events emitted by `CartManager` after successful persistence.
/// Intended for UI refresh, caching, and integrations.
public enum CartEvent: Sendable, Equatable {
    case cartCreated(CartID)
    case cartUpdated(CartID)
    case cartDeleted(CartID)

    /// Active cart changed for a specific scope.
    case activeCartChanged(storeID: StoreID, profileID: UserProfileID?, cartID: CartID?)
}

// MARK: - Use case example
//
// Example: UI layer observing cart changes
//
// Task {
//     let stream = await cartManager.observeEvents()
//     for await event in stream {
//         switch event {
//         case .cartCreated(let id):
//             // Refresh cart list, or load cart by id.
//             break
//         case .cartUpdated(let id):
//             // Refresh cart UI / totals.
//             break
//         case .cartDeleted(let id):
//             // Remove from UI.
//             break
//         case .activeCartChanged(let storeID, let profileID, let cartID):
//             // Update "current cart" state for this scope.
//             break
//         }
//     }
// }
//
// Combine wrapper (UIKit/SwiftUI projects already using Combine):
//
// #if canImport(Combine)
// Task { @MainActor in
//     let publisher = await cartManager.eventsPublisher()
//     publisher
//         .sink { event in
//             // Handle event
//         }
//         .store(in: &cancellables)
// }
// #endif
