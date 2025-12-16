import Foundation
import CoreData

public struct CoreDataCartStoreConfiguration: Sendable {
    
    /// Custom merge policy
    public enum MergePolicy: String, Sendable {
        case propertyObjectTrump
        case propertyStoreTrump
        case overwrite
        case rollback
        // (add more later if needed)
    }
    
    /// Name of the compiled Core Data model (`CartStorage.momd`).
    public let modelName: String
    
    /// If `true`, uses `NSInMemoryStoreType` (tests / previews).
    public let inMemory: Bool
    
    /// Optional explicit store URL for SQLite (host-controlled).
    /// If `nil` and `inMemory == false`, Core Data chooses its default location.
    public let storeURL: URL?
    
    /// Custom merge policy (defaults to "object wins" to reduce conflicts).
    public let mergePolicy: MergePolicy
    
    public init(
        modelName: String = "CartStorage",
        inMemory: Bool = false,
        storeURL: URL? = nil,
        mergePolicy: MergePolicy = .propertyObjectTrump
    ) {
        self.modelName = modelName
        self.inMemory = inMemory
        self.storeURL = storeURL
        self.mergePolicy = mergePolicy
    }
}
