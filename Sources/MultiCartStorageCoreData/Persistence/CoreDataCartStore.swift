import Foundation
import CoreData

/// Core Data stack wrapper used by `MultiCartStorageCoreData`.
///
/// This type is Infrastructure-only:
/// - It owns the `NSPersistentContainer` lifecycle.
/// - It loads the `.momd` model from `Bundle.module` (SwiftPM resources).
/// - It exposes a single `perform(_:)` entry point for running work on a dedicated
///   background context to keep Core Data thread confinement correct.
public actor CoreDataCartStore {
    
    // MARK: - Core Data
    
    /// The backing Core Data persistent container.
    public let container: NSPersistentContainer
    
    /// Dedicated background context for store operations.
    ///
    /// All reads/writes should happen using `perform(_:)` so that Core Data's
    /// threading model is respected and errors propagate predictably.
    private let backgroundContext: NSManagedObjectContext
    
    // MARK: - Init
    
    /// Creates a new Core Data store wrapper.
    ///
    /// - Parameter configuration: Host-configurable store settings, including in-memory mode and store URL.
    /// - Throws: `CoreDataCartStoreError` if the model cannot be found/loaded or if the persistent store fails to load.
    public init(configuration: CoreDataCartStoreConfiguration = .init()) async throws {
        let model = try Self.loadManagedObjectModel(modelName: configuration.modelName)
        
        let container = NSPersistentContainer(
            name: configuration.modelName,
            managedObjectModel: model
        )
        
        let description = NSPersistentStoreDescription()
        
        if configuration.inMemory {
            description.type = NSInMemoryStoreType
            description.url = URL(fileURLWithPath: "/dev/null")
        } else {
            description.type = NSSQLiteStoreType
            if let url = configuration.storeURL {
                description.url = url
            }
        }
        
        // Default migrations behavior (safe for SDK consumers).
        description.shouldInferMappingModelAutomatically = true
        description.shouldMigrateStoreAutomatically = true
        
        container.persistentStoreDescriptions = [description]
        
        try await Self.loadPersistentStores(for: container)
        
        // Configure contexts (merge policy + auto-merge)
        let policy = configuration.mergePolicy.coreDataPolicy
        
        container.viewContext.mergePolicy = policy
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.name = "MultiCartStorageCoreData.viewContext"
        
        let bg = container.newBackgroundContext()
        bg.mergePolicy = policy
        bg.name = "MultiCartStorageCoreData.backgroundContext"
        
        self.container = container
        self.backgroundContext = bg
    }
    
    // MARK: - Context helper
    
    /// Executes a unit of work on the store's background context.
    ///
    /// This is the primary integration point for persistence operations
    ///
    /// - Parameter work: A closure executed on the background context.
    /// - Returns: A value produced by the closure.
    /// - Throws: Any error thrown by the closure.
    public func perform<T: Sendable>(
        _ work: @escaping @Sendable (NSManagedObjectContext) throws -> T
    ) async throws -> T {
        let boxedContext = UncheckedSendableBox(backgroundContext)
        
        return try await withCheckedThrowingContinuation { continuation in
            boxedContext.value.perform {
                do {
                    let result = try work(boxedContext.value)
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    // MARK: - Model loading
    
    private static func loadManagedObjectModel(modelName: String) throws -> NSManagedObjectModel {
        // SwiftPM resources are stored in Bundle.module (not Bundle.main).
        let bundle = Bundle.module
        
        guard let url = bundle.url(forResource: modelName, withExtension: "momd")
                ?? bundle.url(forResource: modelName, withExtension: "mom")
        else {
            throw CoreDataCartStoreError.modelNotFound(modelName: modelName)
        }
        
        guard let model = NSManagedObjectModel(contentsOf: url) else {
            throw CoreDataCartStoreError.modelLoadFailed(modelName: modelName)
        }
        
        return model
    }
    
    private static func loadPersistentStores(for container: NSPersistentContainer) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            container.loadPersistentStores { _, error in
                if let error {
                    continuation.resume(
                        throwing: CoreDataCartStoreError.persistentStoreLoadFailed(underlying: error)
                    )
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }
}

// MARK: - Merge policy mapping

private extension CoreDataCartStoreConfiguration.MergePolicy {
    var coreDataPolicy: NSMergePolicy {
        switch self {
        case .propertyObjectTrump: return NSMergePolicy.mergeByPropertyObjectTrump
        case .propertyStoreTrump: return NSMergePolicy.mergeByPropertyStoreTrump
        case .overwrite: return NSMergePolicy.overwrite
        case .rollback: return NSMergePolicy.rollback
        }
    }
}
