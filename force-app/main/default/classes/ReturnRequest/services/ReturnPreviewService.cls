public inherited sharing class ReturnPreviewService {
  public static CreateReturnPageResult loadCreateReturnPage(Id orderId) {
    CreateReturnPageResult pageResult = new CreateReturnPageResult();

    if (orderId == null) {
      return failure(
        pageResult,
        'ORDER_ID_REQUIRED',
        'Đơn hàng không được để trống.'
      );
    }

    Order orderRecord = ReturnCreatePageSelector.selectOrderHeader(orderId);

    if (orderRecord == null) {
      return failure(pageResult, 'ORDER_NOT_FOUND', 'Không tìm thấy đơn hàng.');
    }

    List<OrderItem> orderItems = ReturnCreatePageSelector.selectOrderItems(
      orderId
    );

    pageResult.header = buildHeader(orderRecord);

    if (orderItems.isEmpty()) {
      return failure(
        pageResult,
        'ORDER_ITEMS_NOT_FOUND',
        'Đơn hàng không có sản phẩm.'
      );
    }

    Set<Id> orderItemIds = new Set<Id>();

    for (OrderItem orderItem : orderItems) {
      orderItemIds.add(orderItem.Id);
    }

    /*
     * REQ-05:
     * Kiểm tra category policy và return deadline.
     */
    Map<Id, ReturnEligibilityResult> eligibilityByOrderItemId = ReturnEligibilityService.evaluate(
      orderItemIds
    );

    /*
     * REQ-06:
     * Lấy tổng quantity đang hoặc đã được trả.
     *
     * Không gọi ReturnQuantityService.evaluate() ở đây
     * vì user chưa nhập requested quantity.
     */
    Map<Id, Decimal> activeReturnedByOrderItemId = ReturnRequestLineSelector.sumActiveReturnedQuantityByOrderItem(
      orderItemIds
    );

    for (OrderItem orderItem : orderItems) {
      ReturnEligibilityResult eligibility = eligibilityByOrderItemId.get(
        orderItem.Id
      );

      Decimal activeReturnedQuantity = getQuantity(
        activeReturnedByOrderItemId,
        orderItem.Id
      );

      Decimal remainingQuantity = Math.max(
        0,
        orderItem.Quantity - activeReturnedQuantity
      );

      CreateReturnOrderLine line = buildLine(
        orderItem,
        eligibility,
        activeReturnedQuantity,
        remainingQuantity
      );

      pageResult.lines.add(line);
    }

    pageResult.success = true;
    pageResult.totalEstimatedRefund = 0;
    pageResult.approvalLevel = null;
    pageResult.canSubmit = false;
    pageResult.code = 'CREATE_RETURN_PAGE_LOADED';
    pageResult.message = 'Đã tải thông tin đơn hàng.';

    System.debug(
      LoggingLevel.INFO,
      'REQ-04 | Create Return page loaded' +
        ' | orderId=' +
        orderId +
        ' | lineCount=' +
        pageResult.lines.size()
    );

    return pageResult;
  }

  private static CreateReturnOrderHeader buildHeader(Order orderRecord) {
    CreateReturnOrderHeader header = new CreateReturnOrderHeader();

    header.orderId = orderRecord.Id;
    header.orderNumber = orderRecord.OrderNumber;

    header.customerId = orderRecord.AccountId;

    header.customerName = orderRecord.Account == null
      ? null
      : orderRecord.Account.Name;

    header.customerPhone = orderRecord.Account == null
      ? null
      : orderRecord.Account.Phone;

    header.purchaseDate = orderRecord.EffectiveDate;

    header.deliveryDate = orderRecord.Delivery_Date__c;

    header.storeId = orderRecord.Store__c;

    header.storeName = orderRecord.Store__r == null
      ? null
      : orderRecord.Store__r.Name;

    header.storeCode = orderRecord.Store__r == null
      ? null
      : orderRecord.Store__r.Store_Code__c;

    return header;
  }

  private static CreateReturnOrderLine buildLine(
    OrderItem orderItem,
    ReturnEligibilityResult eligibility,
    Decimal activeReturnedQuantity,
    Decimal remainingQuantity
  ) {
    CreateReturnOrderLine line = new CreateReturnOrderLine();

    line.orderItemId = orderItem.Id;
    line.productId = orderItem.Product2Id;

    line.productName = orderItem.Product2 == null
      ? null
      : orderItem.Product2.Name;

    line.sku = orderItem.Product2 == null
      ? null
      : orderItem.Product2.ProductCode;

    line.productFamily = orderItem.Product2 == null
      ? null
      : orderItem.Product2.Family;

    line.unitPricePaid = orderItem.UnitPrice;

    line.purchasedQuantity = orderItem.Quantity;

    line.activeReturnedQuantity = activeReturnedQuantity;

    line.remainingQuantity = remainingQuantity;

    line.requestedQuantity = 0;
    line.reasonCode = null;
    line.conditionCode = null;
    line.refundRate = 0;
    line.estimatedRefundAmount = 0;

    if (eligibility == null) {
      line.eligible = false;
      line.eligibilityCode = 'ELIGIBILITY_CHECK_FAILED';
      line.eligibilityReason = 'Không thể kiểm tra điều kiện trả hàng.';
      line.returnDeadline = null;
    } else {
      line.eligible = eligibility.eligible;

      line.eligibilityCode = eligibility.code;

      line.eligibilityReason = eligibility.message;

      line.returnDeadline = eligibility.returnDeadline;
    }

    /*
     * Dù vẫn còn trong hạn, nếu quantity còn lại bằng 0
     * thì user cũng không được nhập thêm.
     */
    if (line.eligible == true && remainingQuantity <= 0) {
      line.eligible = false;
      line.eligibilityCode = 'NO_REMAINING_QUANTITY';
      line.eligibilityReason = 'Sản phẩm đã được trả hết số lượng đã mua.';
    }

    line.valid = line.eligible;
    line.validationMessage = line.eligible ? null : line.eligibilityReason;

    return line;
  }

  private static Decimal getQuantity(
    Map<Id, Decimal> quantitiesByOrderItemId,
    Id orderItemId
  ) {
    Decimal quantity = quantitiesByOrderItemId.get(orderItemId);

    return quantity == null ? 0 : quantity;
  }

  private static CreateReturnPageResult failure(
    CreateReturnPageResult pageResult,
    String code,
    String message
  ) {
    pageResult.success = false;
    pageResult.canSubmit = false;
    pageResult.code = code;
    pageResult.message = message;

    System.debug(
      LoggingLevel.WARN,
      'REQ-04 | Load Create Return page failed' +
        ' | code=' +
        code +
        ' | message=' +
        message
    );

    return pageResult;
  }

  public static CreateReturnPageResult previewReturn(CreateReturnInput input) {
    CreateReturnPageResult previewResult = new CreateReturnPageResult();

    if (
      input == null ||
      input.orderId == null ||
      input.lines == null ||
      input.lines.isEmpty()
    ) {
      return failure(
        previewResult,
        'PREVIEW_INPUT_REQUIRED',
        'Chưa có sản phẩm được chọn để tính tiền hoàn.'
      );
    }

    Order orderRecord = ReturnCreatePageSelector.selectOrderHeader(
      input.orderId
    );

    if (orderRecord == null) {
      return failure(
        previewResult,
        'ORDER_NOT_FOUND',
        'Không tìm thấy đơn hàng.'
      );
    }

    List<OrderItem> orderItems = ReturnCreatePageSelector.selectOrderItems(
      input.orderId
    );

    Map<Id, OrderItem> orderItemsById = new Map<Id, OrderItem>();

    for (OrderItem orderItem : orderItems) {
      orderItemsById.put(orderItem.Id, orderItem);
    }

    Map<Id, CreateReturnLineInput> inputsByOrderItemId = new Map<Id, CreateReturnLineInput>();

    Map<Id, Decimal> requestedQuantities = new Map<Id, Decimal>();

    for (CreateReturnLineInput lineInput : input.lines) {
      if (lineInput == null || lineInput.orderItemId == null) {
        continue;
      }

      /*
       * Nếu cùng OrderItem xuất hiện nhiều lần,
       * preview coi là input không hợp lệ.
       */
      if (inputsByOrderItemId.containsKey(lineInput.orderItemId)) {
        return failure(
          previewResult,
          'DUPLICATE_ORDER_ITEM',
          'Một sản phẩm không được xuất hiện nhiều lần.'
        );
      }

      inputsByOrderItemId.put(lineInput.orderItemId, lineInput);

      requestedQuantities.put(
        lineInput.orderItemId,
        lineInput.requestedQuantity
      );
    }

    if (inputsByOrderItemId.isEmpty()) {
      return failure(
        previewResult,
        'NO_SELECTED_LINES',
        'Phải chọn ít nhất một sản phẩm để trả.'
      );
    }

    Set<Id> selectedOrderItemIds = inputsByOrderItemId.keySet();

    Map<Id, ReturnEligibilityResult> eligibilityResults = ReturnEligibilityService.evaluate(
      selectedOrderItemIds
    );

    Map<Id, ReturnQuantityResult> quantityResults = ReturnQuantityService.evaluate(
      requestedQuantities
    );

    Boolean allSelectedLinesValid = true;
    Boolean hasPositiveQuantity = false;
    Decimal totalEstimatedRefund = 0;

    for (Id orderItemId : selectedOrderItemIds) {
      CreateReturnOrderLine previewLine = new CreateReturnOrderLine();

      previewLine.orderItemId = orderItemId;

      CreateReturnLineInput lineInput = inputsByOrderItemId.get(orderItemId);

      OrderItem orderItem = orderItemsById.get(orderItemId);

      if (orderItem == null) {
        previewLine.valid = false;
        previewLine.eligible = false;
        previewLine.validationMessage = 'Sản phẩm không thuộc đơn hàng.';

        allSelectedLinesValid = false;
        previewResult.lines.add(previewLine);
        continue;
      }

      populateProductFields(previewLine, orderItem);

      previewLine.requestedQuantity = lineInput.requestedQuantity;

      previewLine.reasonCode = normalizeCode(lineInput.reasonCode);

      previewLine.conditionCode = normalizeCode(lineInput.conditionCode);

      ReturnEligibilityResult eligibility = eligibilityResults.get(orderItemId);

      applyEligibility(previewLine, eligibility);

      ReturnQuantityResult quantityResult = quantityResults.get(orderItemId);

      applyQuantity(previewLine, quantityResult);

      if (
        lineInput.requestedQuantity != null &&
        lineInput.requestedQuantity > 0
      ) {
        hasPositiveQuantity = true;
      }

      if (
        previewLine.eligible != true ||
        quantityResult == null ||
        quantityResult.valid != true
      ) {
        previewLine.valid = false;
        allSelectedLinesValid = false;
        previewResult.lines.add(previewLine);
        continue;
      }

      if (
        String.isBlank(previewLine.reasonCode) ||
        String.isBlank(previewLine.conditionCode)
      ) {
        previewLine.valid = false;
        previewLine.validationMessage = 'Vui lòng chọn lý do và tình trạng sản phẩm.';

        allSelectedLinesValid = false;
        previewResult.lines.add(previewLine);
        continue;
      }

      ReturnRefundResult refundResult = ReturnRefundCalculationService.calculate(
        orderItem.UnitPrice,
        lineInput.requestedQuantity,
        previewLine.reasonCode,
        previewLine.conditionCode
      );

      previewLine.refundRate = refundResult.refundRate;

      previewLine.estimatedRefundAmount = refundResult.refundAmount;

      previewLine.valid = refundResult.valid;

      previewLine.validationMessage = refundResult.valid
        ? null
        : refundResult.message;

      if (refundResult.valid == true) {
        totalEstimatedRefund += refundResult.refundAmount;
      } else {
        allSelectedLinesValid = false;
      }

      previewResult.lines.add(previewLine);
    }

    previewResult.totalEstimatedRefund = totalEstimatedRefund;

    if (totalEstimatedRefund > 0 && orderRecord.AccountId != null) {
      previewResult.approvalLevel = ApprovalRoutingService.determineRequiredApprovalLevel(
        orderRecord.AccountId,
        totalEstimatedRefund
      );
    }

    previewResult.canSubmit =
      hasPositiveQuantity &&
      allSelectedLinesValid &&
      totalEstimatedRefund > 0;

    previewResult.success = true;
    previewResult.code = 'RETURN_PREVIEW_CALCULATED';

    previewResult.message = previewResult.canSubmit
      ? 'Dữ liệu yêu cầu trả hàng hợp lệ.'
      : 'Vui lòng kiểm tra các dòng chưa hợp lệ.';

    System.debug(
      LoggingLevel.INFO,
      'REQ-04 | Preview calculated' +
        ' | orderId=' +
        input.orderId +
        ' | selectedLineCount=' +
        previewResult.lines.size() +
        ' | totalEstimatedRefund=' +
        previewResult.totalEstimatedRefund +
        ' | approvalLevel=' +
        previewResult.approvalLevel +
        ' | canSubmit=' +
        previewResult.canSubmit
    );

    return previewResult;
  }

  private static void populateProductFields(
    CreateReturnOrderLine line,
    OrderItem orderItem
  ) {
    line.productId = orderItem.Product2Id;

    line.productName = orderItem.Product2 == null
      ? null
      : orderItem.Product2.Name;

    line.sku = orderItem.Product2 == null
      ? null
      : orderItem.Product2.ProductCode;

    line.productFamily = orderItem.Product2 == null
      ? null
      : orderItem.Product2.Family;

    line.unitPricePaid = orderItem.UnitPrice;

    line.purchasedQuantity = orderItem.Quantity;
  }

  private static void applyEligibility(
    CreateReturnOrderLine line,
    ReturnEligibilityResult eligibility
  ) {
    if (eligibility == null) {
      line.eligible = false;
      line.eligibilityCode = 'ELIGIBILITY_CHECK_FAILED';
      line.eligibilityReason = 'Không thể kiểm tra điều kiện trả hàng.';
      line.valid = false;
      line.validationMessage = line.eligibilityReason;
      return;
    }

    line.eligible = eligibility.eligible;
    line.eligibilityCode = eligibility.code;
    line.eligibilityReason = eligibility.message;
    line.returnDeadline = eligibility.returnDeadline;

    if (eligibility.eligible != true) {
      line.valid = false;
      line.validationMessage = eligibility.message;
    }
  }

  private static void applyQuantity(
    CreateReturnOrderLine line,
    ReturnQuantityResult quantityResult
  ) {
    if (quantityResult == null) {
      line.valid = false;
      line.validationMessage = 'Không thể kiểm tra số lượng còn lại.';
      return;
    }

    line.purchasedQuantity = quantityResult.purchasedQuantity;

    line.activeReturnedQuantity = quantityResult.activeReturnedQuantity;

    line.remainingQuantity = quantityResult.remainingQuantity;

    if (quantityResult.valid != true) {
      line.valid = false;
      line.validationMessage = quantityResult.message;
    }
  }

  private static String normalizeCode(String code) {
    return String.isBlank(code) ? null : code.trim().toUpperCase();
  }
}
