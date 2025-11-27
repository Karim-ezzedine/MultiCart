# MultiCart

A modular, local multi-cart engine for iOS apps.

MultiCart lets you manage multiple carts per user/profile/store, with pluggable storage (Core Data, SwiftData, or your own) and configurable pricing / validation / promotion engines.

> **Status:** WIP – Phase 1 (Local Multi Cart Core).  
> APIs and behavior may change until v1.0 is tagged.

---

## Requirements

- **iOS:** 15.0+
- **Swift:** 5.9+
- **Xcode:** 15+ (SwiftData-based storage requires iOS 17 / a SwiftData-capable SDK)

SwiftData-based storage lives in a separate target and is only available on **iOS 17+**.

---

## Targets / Modules

- **`MultiCartCore`**  
  Core domain types (`Cart`, `CartItem`, `CartTotals`, `Money`, etc.), `CartManager`, configuration, and extension-point protocols (pricing, validation, promotions, analytics, conflict resolution, cart ID generation).

- **`MultiCartStorageCoreData`**  
  Core Data–based `CartStore` implementation (iOS 15+).

- **`MultiCartStorageSwiftData`**  
  SwiftData-based `CartStore` implementation (iOS 17+; types are guarded with `@available(iOS 17, *)` and `#if canImport(SwiftData)`).

- **`MultiCartTestingSupport`**  
  Test helpers (fakes, in-memory stores, builders) for unit and integration tests.

Most of your app code will only need **`MultiCartCore`**; storage targets are typically used in the composition / DI layer.

---

## Installation (Swift Package Manager)

### Xcode

1. In your app project, open  
   **File → Add Packages…**
2. Enter the repo URL, for example:

   ```text
   https://github.com/Karim-ezzedine/MultiCart

