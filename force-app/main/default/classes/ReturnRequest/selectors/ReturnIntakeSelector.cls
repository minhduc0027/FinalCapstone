public inherited sharing class ReturnIntakeSelector {
  public static Order selectOrderById(Id orderId) {
    if (orderId == null) {
      return null;
    }

    List<Order> orders = [
      SELECT
        Id,
        OrderNumber,
        AccountId,
        Store__c,
        Delivery_Date__c,
        EffectiveDate,
        Status
      FROM Order
      WHERE Id = :orderId
      LIMIT 1
    ];

    return orders.isEmpty() ? null : orders[0];
  }

  public static Map<Id, OrderItem> selectAndLockOrderItems(
    Id orderId,
    Set<Id> orderItemIds
  ) {
    Map<Id, OrderItem> itemsById = new Map<Id, OrderItem>();

    if (orderId == null || orderItemIds == null || orderItemIds.isEmpty()) {
      return itemsById;
    }

    for (OrderItem item : [
      SELECT
        Id,
        OrderId,
        Order.AccountId,
        Order.Store__c,
        Order.Delivery_Date__c,
        Product2Id,
        Product2.Name,
        Product2.ProductCode,
        Product2.Family,
        Quantity,
        UnitPrice
      FROM OrderItem
      WHERE Id IN :orderItemIds AND OrderId = :orderId
      FOR UPDATE
    ]) {
      itemsById.put(item.Id, item);
    }

    System.debug(
      LoggingLevel.INFO,
      'REQ-04 | Locked Order Items' +
        ' | orderId=' +
        orderId +
        ' | requestedIds=' +
        orderItemIds +
        ' | lockedCount=' +
        itemsById.size()
    );

    return itemsById;
  }
}
