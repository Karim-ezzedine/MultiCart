import Foundation

/// Errors emitted by `CoreDataCartStore`.
///
/// These errors represent failures at the Infrastructure layer when
/// initializing the Core Data stack or translating persisted data
/// into valid domain models.
public enum CoreDataCartStoreError: Error, Sendable {

    /// The compiled Core Data model (`.momd` / `.mom`) could not be found
    /// in the SwiftPM resource bundle.
    case modelNotFound(modelName: String)

    /// The Core Data model was found but failed to load into
    /// `NSManagedObjectModel` (corrupted or incompatible resource).
    case modelLoadFailed(modelName: String)

    /// The persistent store failed to load or migrate.
    ///
    /// The underlying error is preserved for debugging and diagnostics.
    case persistentStoreLoadFailed(underlying: Error)

    /// The persistent store contains invalid or incomplete data that
    /// cannot be mapped to a valid domain model.
    ///
    /// This typically indicates a schema mismatch, manual database
    /// corruption, or an unexpected migration state.
    case dataCorrupted(entity: String)
}
