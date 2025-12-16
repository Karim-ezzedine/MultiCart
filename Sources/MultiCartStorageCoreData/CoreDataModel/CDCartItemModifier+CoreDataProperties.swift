public import Foundation
public import CoreData


public typealias CDCartItemModifierCoreDataPropertiesSet = NSSet

extension CDCartItemModifier {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<CDCartItemModifier> {
        return NSFetchRequest<CDCartItemModifier>(entityName: "CDCartItemModifier")
    }

    @NSManaged public var id: String?
    @NSManaged public var name: String?
    @NSManaged public var priceDeltaAmount: NSDecimalNumber?
    @NSManaged public var priceDeltaCurrencyCode: String?
    @NSManaged public var item: CDCartItem?

}

extension CDCartItemModifier : Identifiable {

}
