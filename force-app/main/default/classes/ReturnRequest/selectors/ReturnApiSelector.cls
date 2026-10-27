public inherited sharing class ReturnApiSelector {
  public static Order selectOrder(
    String orderNumber,
    String customerPhone,
    String storeCode
  ) {
    if (
      String.isBlank(orderNumber) ||
      String.isBlank(customerPhone) ||
      String.isBlank(storeCode)
    ) {
      return null;
    }

    List<Order> orders = [
      SELECT
        Id,
        OrderNumber,
        AccountId,
        Account.Phone,
        Store__c,
        Store__r.Store_Code__c,
        Delivery_Date__c,
        EffectiveDate,
        Status
      FROM Order
      WHERE
        OrderNumber = :orderNumber
        AND Account.Phone = :customerPhone
        AND Store__r.Store_Code__c = :storeCode
      LIMIT 1
    ];

    return orders.isEmpty() ? null : orders[0];
  }

  public static Map<String, OrderItem> selectOrderItemsBySku(
    Id orderId,
    Set<String> skus
  ) {
    Map<String, OrderItem> itemsBySku = new Map<String, OrderItem>();

    if (orderId == null || skus == null || skus.isEmpty()) {
      return itemsBySku;
    }

    for (OrderItem item : [
      SELECT Id, OrderId, Product2Id, Product2.ProductCode, Quantity, UnitPrice
      FROM OrderItem
      WHERE OrderId = :orderId AND Product2.ProductCode IN :skus
    ]) {
      itemsBySku.put(normalizeCode(item.Product2.ProductCode), item);
    }

    return itemsBySku;
  }

  public static Return_Request__c selectByExternalRequestId(
    String externalRequestId
  ) {
    if (String.isBlank(externalRequestId)) {
      return null;
    }

    List<Return_Request__c> requests = [
      SELECT
        Id,
        Name,
        Order__c,
        Order__r.OrderNumber,
        Status__c,
        Required_Approval_Level__c,
        Estimated_Refund_Amount__c,
        Actual_Refund_Amount__c,
        External_Request_ID__c,
        CreatedDate
      FROM Return_Request__c
      WHERE External_Request_ID__c = :externalRequestId
      LIMIT 1
    ];

    return requests.isEmpty() ? null : requests[0];
  }

  public static Return_Request__c selectByRequestNumber(String requestNumber) {
    if (String.isBlank(requestNumber)) {
      return null;
    }

    List<Return_Request__c> requests = [
      SELECT
        Id,
        Name,
        Order__c,
        Order__r.OrderNumber,
        Status__c,
        Required_Approval_Level__c,
        Estimated_Refund_Amount__c,
        Actual_Refund_Amount__c,
        External_Request_ID__c,
        CreatedDate
      FROM Return_Request__c
      WHERE Name = :requestNumber
      LIMIT 1
    ];

    return requests.isEmpty() ? null : requests[0];
  }

  public static Return_Request__c selectById(Id requestId) {
    if (requestId == null) {
      return null;
    }

    List<Return_Request__c> requests = [
      SELECT
        Id,
        Name,
        Order__c,
        Order__r.OrderNumber,
        Status__c,
        Required_Approval_Level__c,
        Estimated_Refund_Amount__c,
        Actual_Refund_Amount__c,
        External_Request_ID__c,
        CreatedDate
      FROM Return_Request__c
      WHERE Id = :requestId
      LIMIT 1
    ];

    return requests.isEmpty() ? null : requests[0];
  }

  public static List<Return_Request_Line__c> selectLines(Id requestId) {
    if (requestId == null) {
      return new List<Return_Request_Line__c>();
    }

    return [
      SELECT
        Id,
        Order_Item__c,
        Product__c,
        Product__r.ProductCode,
        Requested_Quantity__c,
        Unit_Price_Paid__c,
        Estimated_Refund_Rate__c,
        Estimated_Refund_Amount__c
      FROM Return_Request_Line__c
      WHERE Return_Request__c = :requestId
      ORDER BY CreatedDate
    ];
  }

  public static List<Return_Request__History> selectStatusHistory(
    Id requestId
  ) {
    if (requestId == null) {
      return new List<Return_Request__History>();
    }

    return [
      SELECT ParentId, Field, OldValue, NewValue, CreatedDate
      FROM Return_Request__History
      WHERE ParentId = :requestId AND Field = 'Status__c'
      ORDER BY CreatedDate
    ];
  }

  private static String normalizeCode(String value) {
    return String.isBlank(value) ? null : value.trim().toUpperCase();
  }
}
