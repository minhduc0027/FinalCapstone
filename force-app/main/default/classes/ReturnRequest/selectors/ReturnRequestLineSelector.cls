public inherited sharing class ReturnRequestLineSelector {
  private static final Set<String> EXCLUDED_STATUSES = new Set<String>{
    StateTransitionService.STATUS_REJECTED,
    StateTransitionService.STATUS_CANCELLED
  };

  public static Map<Id, Decimal> sumActiveReturnedQuantityByOrderItem(
    Set<Id> orderItemIds
  ) {
    Map<Id, Decimal> quantitiesByOrderItemId = new Map<Id, Decimal>();

    if (orderItemIds == null || orderItemIds.isEmpty()) {
      return quantitiesByOrderItemId;
    }

    for (AggregateResult aggregateRow : [
      SELECT Order_Item__c orderItemId, SUM(Requested_Quantity__c) totalQuantity
      FROM Return_Request_Line__c
      WHERE
        Order_Item__c IN :orderItemIds
        AND Return_Request__r.Status__c NOT IN :EXCLUDED_STATUSES
      GROUP BY Order_Item__c
    ]) {
      Id orderItemId = (Id) aggregateRow.get('orderItemId');

      Decimal totalQuantity = (Decimal) aggregateRow.get('totalQuantity');

      quantitiesByOrderItemId.put(
        orderItemId,
        totalQuantity == null ? 0 : totalQuantity
      );
    }

    System.debug(
      LoggingLevel.INFO,
      'REQ-06 | Active returned quantity' +
        ' | excludedStatuses=' +
        EXCLUDED_STATUSES +
        ' | result=' +
        quantitiesByOrderItemId
    );

    return quantitiesByOrderItemId;
  }
}
