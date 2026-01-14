# CartKit

A modular, local multi-cart SDK for iOS apps.

CartKit lets you manage multiple carts per store and per user scope (guest or profile), with pluggable storage (Core Data, SwiftData, or your own) and configurable pricing/validation/promotion / conflict-resolution engines.

**CartKit at a glance**
- Local-first cart management (no networking)
- Supports guest and profile carts
- Multiple carts per store
- Explicit composition and dependency injection
- Pluggable storage and business policies

> **Status:** WIP  
> APIs and behavior may change until v1.0 is tagged.

---

## Requirements

- **iOS:** 15.0+
- **Swift:** 5.9+
- **Xcode:** 15+
- **SwiftData storage:** iOS 17+ (separate target guarded by availability)

---

## Modules

- **CartKit**  
  Umbrella module that re-exports `CartKitCore` with default storage integrations.  
  Suitable for apps that want a simple, batteries-included setup.
  
- **CartKitCore**
  Domain types (`Cart`, `CartItem`, `Money`, `CartTotals`, etc.), `CartManager`, configuration, and extension-point protocols.

- **CartKitStorageCoreData**  
  Core Data `CartStore` implementation (iOS 15+).

- **CartKitStorageSwiftData**  
  SwiftData `CartStore` implementation (iOS 17+; availability guarded).

- **CartKitTestingSupport**  
  Test helpers (in-memory store, fakes/spies) for unit and integration tests.

Most apps import **`CartKitCore`** in feature code and keep storage selection in the composition/DI layer.  
Apps that prefer a simpler setup may import **`CartKit`** instead.

---

## Installation (Swift Package Manager)

### Xcode

1. **File → Add Packages…**
2. Enter the repository URL:
   ```text
    https://github.com/Karim-ezzedine/CartKit
   ```
   
---

## Configuration & Composition

CartKit is designed around explicit composition at the application boundary.

Applications are expected to assemble a `CartConfiguration` in their dependency-injection or composition layer. This configuration defines how carts behave, where they are stored, and which policies are applied.

> CartKit performs no implicit setup and relies on no global state.
> All behavior is defined through explicit configuration.

### Building a CartConfiguration

**A `CartConfiguration` wires together:**
- Cart storage
- Pricing, validation, and promotion engines
- Catalog conflict handling
- Analytics and logging

The recommended entry point is the asynchronous convenience builder:

`CartConfiguration.configured(...)`

This builder resolves storage, applies safe defaults where appropriate, and returns a fully configured instance ready to be used by `CartManager`.

Composition is intentionally explicit to ensure predictable behavior, testability, and clear ownership of business policies outside the domain.

Tests may bypass this builder and construct CartConfiguration directly.

### Choosing configuration options

Configuration decisions generally fall into two categories:

#### Storage choice

Applications select how carts are persisted (Core Data, SwiftData, or a custom implementation).  
Storage selection is performed once at composition time and remains stable for the lifetime of the configuration.

Details are covered in the *Storage selection* section below.

#### Guest vs profile usage

Guest and profile carts do not require separate configurations.

Both use the same configuration and manager; behavior differences are driven by cart scope and identifiers rather than by distinct setups.

---

## Guest vs Profile semantics

CartKit models guest and profile carts using the same domain type.

### Guest carts

A cart is considered a guest cart when:

`profileID == nil`

Guest carts are local-only, not tied to a user account, and may later be migrated when a user authenticates.

There is no separate “guest cart” type. Guest behavior is a semantic interpretation, not a different model.

### Profile carts

A cart becomes a profile cart when it is associated with a non-nil `profileID`.

Profile carts follow the same lifecycle rules as guest carts and differ only in ownership and scope.

### One-active-cart rule

For a given `(storeID, profileID)` pair, only one cart may be active at a time.

This invariant is enforced by `CartManager`, not by storage implementations.

The rule ensures deterministic cart resolution and simplifies application-level state management.

### Guest → profile migration

When a guest authenticates, applications may choose to migrate the active guest cart to a profile cart.

CartKit provides helper APIs to support this flow, while leaving the timing and strategy of migration entirely to the client.

Migration helpers are designed to preserve cart contents and respect active cart invariants without performing implicit destructive actions.

---

## Storage selection

CartKit does not hardcode a persistence mechanism.

Storage is selected explicitly during configuration and injected into the cart system.

### Using CartStoreFactory

`CartStoreFactory` is responsible for creating a `CartStore` based on a `CartStoragePreference`.

This keeps storage decisions out of the domain layer and avoids platform-specific logic in feature code.

Applications are expected to resolve storage once at composition time.

### iOS 15 vs iOS 17 guidance

**CartKit provides two built-in storage implementations:**
- **Core Data**
  - Available on iOS 15 and later
  - Recommended for apps supporting iOS 15 or 16

- **SwiftData**
  - Available on iOS 17 and later
  - Guarded by availability checks
  - Recommended for iOS 17-only applications

SwiftData support lives in a separate module and is never selected implicitly.

For applications supporting multiple OS versions, Core Data remains the safest default.

### Custom storage

Applications may provide their own `CartStore` implementation.

Custom storage is useful when persistence is handled by an existing system, requires custom synchronization, or is intentionally ephemeral.

Custom implementations must respect domain invariants but are otherwise unconstrained.

---

## Engines & extension points

CartKit keeps the domain model stable and exposes variability through explicit extension points (“engines”). This allows applications to adapt policies (pricing, validation, promotions, conflict handling) without forking domain logic or leaking infrastructure concerns into feature code.

**From a Clean Architecture perspective:**
- **Domain/Core:** Entities and engine protocols define *what* must be true.
- **Application:** `CartManager` orchestrates *when* policies are applied and enforces invariants.
- **Infrastructure:** Concrete engine implementations and persistence are injected at composition time.

### What is an “engine” in CartKit?

An engine is a protocol-backed component that encapsulates a specific business policy, such as:

- How totals are computed
- Which items are allowed and under what constraints
- How promotions are applied
- How conflicts should be detected and resolved

Engines are passed into `CartConfiguration`, making behavior explicit, testable, and deterministic.

### Pricing

The pricing engine is responsible for computing cart totals based on the cart’s contents.

**Typical responsibilities:**
- Subtotal calculation
- Fee and tax inclusion (if applicable)
- Final total computation

**Pricing is intentionally isolated so applications can:**
- Keep calculations consistent with backend rules
- Swap pricing logic per market or experiment
- Test totals deterministically

### Validation

The validation engine determines whether the cart is eligible for progression (for example, before checkout).

**Typical responsibilities include:**
- Item-level rules (quantity bounds, required metadata, etc.)
- Cart-level rules (minimum order value, incompatible combinations, etc.)
- Producing structured validation outcomes

Validation is a key boundary: CartKit can manage carts for guests, but applications often require additional rules before checkout (for example, authentication or delivery availability). Those rules belong in validation policy, not in the domain entities themselves.

### Promotions

Promotions are modeled as policy: how discounts/rewards are discovered, applied, and represented.

**Typical responsibilities include:**
- Applying promo codes
- Automatic offers (buy X get Y, tiered discounts, etc.)
- Updating applied promotions as cart contents change

Promotion behavior varies significantly between products; keeping it behind an engine prevents domain model churn and supports A/B testing and regional rules.

### Catalog conflict handling (client responsibility)

**CartKit supports multiple carts and multiple scopes, which introduces the possibility of conflicts when:**
- A product becomes unavailable
- Catalog data changes (price, modifiers, constraints)
- A cart is restored after time has passed
- Two sources propose differing representations for the same item

**CartKit exposes explicit conflict detection and resolution extension points so the client can define the correct business behavior. Examples include:**
- “Remove unavailable items automatically.”
- “Keep items but mark them invalid until the user confirms.”
- “Prefer latest catalog price vs preserve original price.”

This is intentionally client-owned because conflict strategy is product-specific and often UX-driven.

### Analytics and logging as extension points

CartKit emits domain-level signals (such as cart changes and lifecycle events) through dedicated sinks.

This keeps:
- Domain logic free from analytics vendors
- Instrumentation consistent and testable
- Event emission deterministic

Applications can plug in their own analytics/logging implementations in the configuration layer without affecting the domain.

### Practical guidance

**Recommended defaults:**
- Keep engines lightweight and deterministic.
- Avoid networking inside engines where possible (prefer pre-fetched inputs).
- Treat engines as pure policy objects: given the same input, they should produce the same output.
- For tests, inject fakes/spies to assert orchestration and outcomes.

---

## Testing examples

CartKit is designed to be testable by construction.

All cart behavior is driven through explicit dependencies (such as storage and policies), allowing tests to run deterministically without relying on UI layers or platform persistence.

This section demonstrates a basic cart flow using Swift Testing.

### Testing strategy

Recommended testing principles:

- Interact with carts only through `CartManager`
- Inject test or in-memory `CartStore` implementations
- Rely on default engines unless a test requires custom behavior
- Assert on domain outcomes, not side effects

This approach aligns naturally with test-driven development (TDD).

### Example: basic cart flow

The following example demonstrates a simple end-to-end cart scenario:

1. Create a test cart store
2. Build a minimal configuration
3. Set an active cart
4. Add an item
5. Assert on domain state

```swift

import Testing
import CartKitCore
import CartKitTestingSupport

struct CartFlowTests {

    @Test
    func basicCartFlow() async throws {
        // 1. Create a test store
        let store = InMemoryCartStore()

        // 2. Build a minimal configuration
        let configuration = CartConfiguration(
            cartStore: store
        )

        let manager = CartManager(configuration: configuration)

        // 3. Set an active cart (guest)
        let cart = try await manager.setActiveCart(
            storeID: StoreID("store-1"),
            profileID: nil
        )

        // 4. Add an item
        let cartUpdateResult = try await manager.addItem(
            to: cart.id,
            item: CartItem(
                id: CartItemID.generate(),
                productID: "burger",
                quantity: 1,
                unitPrice: Money(amount: 10, currencyCode: "USD"),
                modifiers: [],
                imageURL: nil
            )
        )

        // 5. Assert domain state
        #expect(cartUpdateResult.cart.items.count == 1)
        #expect(cartUpdateResult.cart.status == .active)
    }
}

```
