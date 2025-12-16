public import Foundation
public import CoreData


public typealias CDCartItemCoreDataPropertiesSet = NSSet

extension CDCartItem {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<CDCartItem> {
        return NSFetchRequest<CDCartItem>(entityName: "CDCartItem")
    }

    @NSManaged public var availableStock: Int32
    @NSManaged public var id: String?
    @NSManaged public var imageURL: String?
    @NSManaged public var productId: String?
    @NSManaged public var quantity: Int32
    @NSManaged public var totalPriceAmount: NSDecimalNumber?
    @NSManaged public var totalPriceCurrencyCode: String?
    @NSManaged public var unitPriceAmount: NSDecimalNumber?
    @NSManaged public var unitPriceCurrencyCode: String?
    @NSManaged public var cart: CDCart?
    @NSManaged public var modifiers: NSSet?

}

// MARK: Generated accessors for modifiers
extension CDCartItem {

    @objc(addModifiersObject:)
    @NSManaged public func addToModifiers(_ value: CDCartItemModifier)

    @objc(removeModifiersObject:)
    @NSManaged public func removeFromModifiers(_ value: CDCartItemModifier)

    @objc(addModifiers:)
    @NSManaged public func addToModifiers(_ values: NSSet)

    @objc(removeModifiers:)
    @NSManaged public func removeFromModifiers(_ values: NSSet)

}

extension CDCartItem : Identifiable {

}
