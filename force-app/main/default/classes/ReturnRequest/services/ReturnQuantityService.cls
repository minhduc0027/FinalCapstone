public inherited sharing class ReturnQuantityService {
  public static Map<Id, ReturnQuantityResult> evaluate(
    Map<Id, Decimal> requestedQuantityByOrderItemId
  ) {
    Map<Id, ReturnQuantityResult> resultsByOrderItemId = new Map<Id, ReturnQuantityResult>();

    if (
      requestedQuantityByOrderItemId == null ||
      requestedQuantityByOrderItemId.isEmpty()
    ) {
      return resultsByOrderItemId;
    }

    Set<Id> orderItemIds = requestedQuantityByOrderItemId.keySet();

    System.debug(
      LoggingLevel.INFO,
      'REQ-06 | Quantity evaluation started' +
        ' | input=' +
        requestedQuantityByOrderItemId
    );

    Map<Id, OrderItem> orderItemsById = ReturnOrderItemSelector.selectByIds(
      orderItemIds
    );

    Map<Id, Decimal> activeQuantitiesByOrderItemId = ReturnRequestLineSelector.sumActiveReturnedQuantityByOrderItem(
      orderItemIds
    );

    for (Id orderItemId : orderItemIds) {
      Decimal requestedQuantity = requestedQuantityByOrderItemId.get(
        orderItemId
      );

      OrderItem orderItem = orderItemsById.get(orderItemId);

      if (orderItem == null) {
        addResult(
          resultsByOrderItemId,
          ReturnQuantityResult.create(
            orderItemId,
            0,
            0,
            requestedQuantity,
            false,
            'ORDER_ITEM_NOT_FOUND',
            'Không tìm thấy sản phẩm trong đơn hàng.'
          )
        );
        continue;
      }

      Decimal activeReturnedQuantity = getQuantity(
        activeQuantitiesByOrderItemId,
        orderItemId
      );

      if (requestedQuantity == null || requestedQuantity <= 0) {
        addResult(
          resultsByOrderItemId,
          ReturnQuantityResult.create(
            orderItemId,
            orderItem.Quantity,
            activeReturnedQuantity,
            requestedQuantity,
            false,
            'INVALID_REQUESTED_QUANTITY',
            'Số lượng yêu cầu trả phải lớn hơn 0.'
          )
        );
        continue;
      }

      Decimal remainingQuantity = Math.max(
        0,
        orderItem.Quantity - activeReturnedQuantity
      );

      Boolean valid = requestedQuantity <= remainingQuantity;

      addResult(
        resultsByOrderItemId,
        ReturnQuantityResult.create(
          orderItemId,
          orderItem.Quantity,
          activeReturnedQuantity,
          requestedQuantity,
          valid,
          valid ? 'QUANTITY_AVAILABLE' : 'QUANTITY_EXCEEDED',
          valid
            ? 'Số lượng yêu cầu trả hợp lệ.'
            : 'Số lượng yêu cầu trả vượt quá số lượng còn lại.'
        )
      );
    }

    System.debug(
      LoggingLevel.INFO,
      'REQ-06 | Quantity evaluation completed' +
        ' | resultCount=' +
        resultsByOrderItemId.size()
    );

    return resultsByOrderItemId;
  }

  private static Decimal getQuantity(
    Map<Id, Decimal> quantitiesByOrderItemId,
    Id orderItemId
  ) {
    Decimal quantity = quantitiesByOrderItemId.get(orderItemId);

    return quantity == null ? 0 : quantity;
  }

  private static void addResult(
    Map<Id, ReturnQuantityResult> resultsByOrderItemId,
    ReturnQuantityResult result
  ) {
    resultsByOrderItemId.put(result.orderItemId, result);

    System.debug(
      LoggingLevel.INFO,
      'REQ-06 | Quantity result' +
        ' | orderItemId=' +
        result.orderItemId +
        ' | purchased=' +
        result.purchasedQuantity +
        ' | activeReturned=' +
        result.activeReturnedQuantity +
        ' | remaining=' +
        result.remainingQuantity +
        ' | requested=' +
        result.requestedQuantity +
        ' | valid=' +
        result.valid +
        ' | code=' +
        result.code
    );
  }
}
