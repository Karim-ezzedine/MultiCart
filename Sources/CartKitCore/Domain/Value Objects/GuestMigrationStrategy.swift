public enum GuestMigrationStrategy: Sendable {
    /// Move the active guest cart into the profile scope (same cart ID).
    case move

    /// Create a new active profile cart (new cart ID), then delete the guest cart.
    case copyAndDelete
}
