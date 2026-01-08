public import Foundation
public import CoreData


public typealias CDCartCoreDataPropertiesSet = NSSet

extension CDCart {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<CDCart> {
        return NSFetchRequest<CDCart>(entityName: "CDCart")
    }

    @NSManaged public var context: String?
    @NSManaged public var createdAt: Date?
    @NSManaged public var displayName: String?
    @NSManaged public var id: String?
    @NSManaged public var maxItemCount: Int32
    @NSManaged public var metadataJSON: Data?
    @NSManaged public var minSubtotalAmount: NSDecimalNumber?
    @NSManaged public var minSubtotalCurrencyCode: String?
    @NSManaged public var profileId: String?
    @NSManaged public var status: String?
    @NSManaged public var storeId: String?
    @NSManaged public var storeImageURL: String?
    @NSManaged public var updatedAt: Date?
    @NSManaged public var items: NSSet?

}

// MARK: Generated accessors for items
extension CDCart {

    @objc(addItemsObject:)
    @NSManaged public func addToItems(_ value: CDCartItem)

    @objc(removeItemsObject:)
    @NSManaged public func removeFromItems(_ value: CDCartItem)

    @objc(addItems:)
    @NSManaged public func addToItems(_ values: NSSet)

    @objc(removeItems:)
    @NSManaged public func removeFromItems(_ values: NSSet)

}

extension CDCart : Identifiable {

}
