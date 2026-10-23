public inherited sharing class ReturnEligibilityService {
  public static Map<Id, ReturnEligibilityResult> evaluate(
    Set<Id> orderItemIds
  ) {
    return evaluate(orderItemIds, Date.today());
  }

  @TestVisible
  private static Map<Id, ReturnEligibilityResult> evaluate(
    Set<Id> orderItemIds,
    Date evaluationDate
  ) {
    Map<Id, ReturnEligibilityResult> resultsByOrderItemId = new Map<Id, ReturnEligibilityResult>();

    if (orderItemIds == null || orderItemIds.isEmpty()) {
      return resultsByOrderItemId;
    }

    Map<Id, OrderItem> orderItemsById = ReturnOrderItemSelector.selectByIds(
      orderItemIds
    );

    Map<String, Return_Category_Policy__mdt> policiesByFamily = ReturnCategoryPolicySelector.selectActivePoliciesByFamily();

    for (Id orderItemId : orderItemIds) {
      OrderItem item = orderItemsById.get(orderItemId);

      if (item == null) {
        resultsByOrderItemId.put(
          orderItemId,
          ReturnEligibilityResult.failure(
            orderItemId,
            'ORDER_ITEM_NOT_FOUND',
            'Không tìm thấy sản phẩm trong đơn hàng.',
            null
          )
        );
        continue;
      }

      if (item.Product2 == null || String.isBlank(item.Product2.Family)) {
        resultsByOrderItemId.put(
          orderItemId,
          ReturnEligibilityResult.failure(
            orderItemId,
            'MISSING_POLICY',
            'Sản phẩm chưa được cấu hình ngành hàng.',
            null
          )
        );
        continue;
      }

      String familyKey = ReturnCategoryPolicySelector.normalizeFamily(
        item.Product2.Family
      );

      Return_Category_Policy__mdt policy = policiesByFamily.get(familyKey);

      if (policy == null) {
        resultsByOrderItemId.put(
          orderItemId,
          ReturnEligibilityResult.failure(
            orderItemId,
            'MISSING_POLICY',
            'Không tìm thấy chính sách trả hàng cho ngành hàng.',
            null
          )
        );
        continue;
      }

      if (policy.Return_Allowed__c != true) {
        resultsByOrderItemId.put(
          orderItemId,
          ReturnEligibilityResult.failure(
            orderItemId,
            'CATEGORY_NOT_RETURNABLE',
            'Ngành hàng này không được phép trả.',
            null
          )
        );
        continue;
      }

      if (item.Order.Delivery_Date__c == null) {
        resultsByOrderItemId.put(
          orderItemId,
          ReturnEligibilityResult.failure(
            orderItemId,
            'MISSING_DELIVERY_DATE',
            'Đơn hàng chưa có ngày giao hàng.',
            null
          )
        );
        continue;
      }

      if (policy.Return_Window_Days__c == null) {
        resultsByOrderItemId.put(
          orderItemId,
          ReturnEligibilityResult.failure(
            orderItemId,
            'MISSING_POLICY',
            'Chính sách chưa cấu hình thời hạn trả hàng.',
            null
          )
        );
        continue;
      }

      Integer returnWindowDays = policy.Return_Window_Days__c.intValue();

      Date returnDeadline = item.Order.Delivery_Date__c.addDays(
        returnWindowDays
      );

      if (evaluationDate > returnDeadline) {
        resultsByOrderItemId.put(
          orderItemId,
          ReturnEligibilityResult.failure(
            orderItemId,
            'RETURN_PERIOD_EXPIRED',
            'Sản phẩm đã quá thời hạn trả hàng.',
            returnDeadline
          )
        );
        continue;
      }

      resultsByOrderItemId.put(
        orderItemId,
        ReturnEligibilityResult.success(orderItemId, returnDeadline)
      );
    }

    return resultsByOrderItemId;
  }
}
