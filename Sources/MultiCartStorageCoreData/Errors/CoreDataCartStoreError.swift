import Foundation

public enum CoreDataCartStoreError: Error, Sendable {
    case modelNotFound(modelName: String)
    case modelLoadFailed(modelName: String)
    case persistentStoreLoadFailed(underlying: Error)
}
