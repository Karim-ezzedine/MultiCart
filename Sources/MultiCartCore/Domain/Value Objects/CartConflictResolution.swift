/// Decision returned when a conflict is detected (e.g. catalog changes).
public enum CartConflictResolution: Sendable {
    /// Use the provided, cleaned-up cart (e.g. with invalid items removed).
    case acceptModifiedCart(Cart)
    
    /// Abort and surface an error back to the caller.
    case rejectWithError(MultiCartError)
}
