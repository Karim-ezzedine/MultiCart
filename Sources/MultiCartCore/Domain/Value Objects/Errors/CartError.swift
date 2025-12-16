/// High-level error type used by Cart core.
public enum CartError: Error, Equatable, Sendable {
    case validationFailed(reason: String)
    case pricingFailed(reason: String)
    case conflict(reason: String)
    case storageFailure(reason: String)
    case unknown
}

