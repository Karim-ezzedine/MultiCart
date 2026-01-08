import Foundation

public struct CartDetailsOverrides: Sendable {
    public var displayName: String?
    public var context: String?
    public var metadata: [String: String]?
    public var storeImageURL: URL?
    public var minSubtotal: Money?
    public var maxItemCount: Int?

    public init(
        displayName: String? = nil,
        context: String? = nil,
        metadata: [String: String]? = nil,
        storeImageURL: URL? = nil,
        minSubtotal: Money? = nil,
        maxItemCount: Int? = nil
    ) {
        self.displayName = displayName
        self.context = context
        self.metadata = metadata
        self.storeImageURL = storeImageURL
        self.minSubtotal = minSubtotal
        self.maxItemCount = maxItemCount
    }
}
