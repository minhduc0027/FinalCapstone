public inherited sharing class ReturnOrderItemSelector {
  public static Map<Id, OrderItem> selectByIds(Set<Id> orderItemIds) {
    Map<Id, OrderItem> itemsById = new Map<Id, OrderItem>();

    if (orderItemIds == null || orderItemIds.isEmpty()) {
      return itemsById;
    }

    for (OrderItem item : [
      SELECT
        Id,
        OrderId,
        Order.Delivery_Date__c,
        Product2Id,
        Product2.Family,
        Quantity,
        UnitPrice
      FROM OrderItem
      WHERE Id IN :orderItemIds
    ]) {
      itemsById.put(item.Id, item);
    }

    return itemsById;
  }
}
