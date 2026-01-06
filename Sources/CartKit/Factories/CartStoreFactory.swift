import Foundation
import CartKitCore
import CartKitStorageCoreData

#if os(iOS) && canImport(SwiftData) && canImport(CartKitStorageSwiftData)
import CartKitStorageSwiftData
#endif

public enum CartStoreFactory {

    public static func makeStore(
        preference: CartStoragePreference
    ) async throws -> any CartStore {

        switch preference {

        case .coreData:
            return try await CoreDataCartStore()

        case .swiftData:
            #if os(iOS) && canImport(SwiftData) && canImport(CartKitStorageSwiftData)
            if #available(iOS 17, *) {
                return try SwiftDataCartStore()
            } else {
                throw CartStoreFactoryError.swiftDataUnavailable
            }
            #else
            throw CartStoreFactoryError.swiftDataUnavailable
            #endif

        case .automatic:
            #if os(iOS) && canImport(SwiftData) && canImport(CartKitStorageSwiftData)
            if #available(iOS 17, *) {
                return try SwiftDataCartStore()
            }
            #endif

            // Fallback for macOS / iOS < 17
            return try await CoreDataCartStore()
        }
    }
}

enum CartStoreFactoryError: Error {
    case swiftDataUnavailable
}
