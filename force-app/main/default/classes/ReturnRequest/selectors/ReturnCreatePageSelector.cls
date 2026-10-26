public inherited sharing class ReturnCreatePageSelector {
  public static Order selectOrderHeader(Id orderId) {
    if (orderId == null) {
      return null;
    }

    List<Order> orders = [
      SELECT
        Id,
        OrderNumber,
        AccountId,
        Account.Name,
        Account.Phone,
        EffectiveDate,
        Delivery_Date__c,
        Store__c,
        Store__r.Name,
        Store__r.Store_Code__c
      FROM Order
      WHERE Id = :orderId
      LIMIT 1
    ];

    return orders.isEmpty() ? null : orders[0];
  }

  public static List<OrderItem> selectOrderItems(Id orderId) {
    if (orderId == null) {
      return new List<OrderItem>();
    }

    return [
      SELECT
        Id,
        OrderId,
        Product2Id,
        Product2.Name,
        Product2.ProductCode,
        Product2.Family,
        Quantity,
        UnitPrice
      FROM OrderItem
      WHERE OrderId = :orderId
      ORDER BY Product2.Name
    ];
  }
}
