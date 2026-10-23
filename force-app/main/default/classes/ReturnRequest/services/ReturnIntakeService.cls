public inherited sharing class ReturnIntakeService {
  public static CreateReturnResult createReturn(CreateReturnInput input) {
    Savepoint savepointRecord = Database.setSavepoint();

    try {
      validateInput(input);

      Map<Id, CreateReturnLineInput> inputLineByOrderItemId = buildInputLineMap(
        input.lines
      );

      Set<Id> orderItemIds = inputLineByOrderItemId.keySet();

      /*
       * Lock OrderItems để chống hai transaction đồng thời
       * cùng tạo Return Request vượt quá purchased quantity.
       */
      Map<Id, OrderItem> lockedOrderItemsById = ReturnIntakeSelector.selectAndLockOrderItems(
        input.orderId,
        orderItemIds
      );

      if (lockedOrderItemsById.size() != orderItemIds.size()) {
        return rollbackFailure(
          savepointRecord,
          'INVALID_ORDER_ITEM',
          'Một hoặc nhiều sản phẩm không thuộc đơn hàng.'
        );
      }

      /*
       * REQ-05:
       * Kiểm tra thời hạn và ngành hàng.
       */
      Map<Id, ReturnEligibilityResult> eligibilityResults = ReturnEligibilityService.evaluate(
        orderItemIds
      );

      for (Id orderItemId : orderItemIds) {
        ReturnEligibilityResult eligibilityResult = eligibilityResults.get(
          orderItemId
        );

        if (eligibilityResult == null || eligibilityResult.eligible != true) {
          String code = eligibilityResult == null
            ? 'ELIGIBILITY_CHECK_FAILED'
            : eligibilityResult.code;

          String message = eligibilityResult == null
            ? 'Không thể kiểm tra điều kiện trả hàng.'
            : eligibilityResult.message;

          return rollbackFailure(savepointRecord, code, message);
        }
      }

      /*
       * REQ-06:
       * Kiểm tra remaining quantity sau khi OrderItem đã lock.
       */
      Map<Id, Decimal> requestedQuantityByOrderItemId = new Map<Id, Decimal>();

      for (Id orderItemId : inputLineByOrderItemId.keySet()) {
        requestedQuantityByOrderItemId.put(
          orderItemId,
          inputLineByOrderItemId.get(orderItemId).requestedQuantity
        );
      }

      Map<Id, ReturnQuantityResult> quantityResults = ReturnQuantityService.evaluate(
        requestedQuantityByOrderItemId
      );

      for (Id orderItemId : orderItemIds) {
        ReturnQuantityResult quantityResult = quantityResults.get(orderItemId);

        if (quantityResult == null || quantityResult.valid != true) {
          String code = quantityResult == null
            ? 'QUANTITY_CHECK_FAILED'
            : quantityResult.code;

          String message = quantityResult == null
            ? 'Không thể kiểm tra số lượng còn lại.'
            : quantityResult.message;

          return rollbackFailure(savepointRecord, code, message);
        }
      }

      /*
       * REQ-07:
       * Tính refund cho từng line.
       */
      Map<Id, ReturnRefundResult> refundResultsByOrderItemId = new Map<Id, ReturnRefundResult>();

      Decimal totalEstimatedRefund = 0;

      for (Id orderItemId : orderItemIds) {
        OrderItem orderItem = lockedOrderItemsById.get(orderItemId);

        CreateReturnLineInput lineInput = inputLineByOrderItemId.get(
          orderItemId
        );

        ReturnRefundResult refundResult = ReturnRefundCalculationService.calculate(
          orderItem.UnitPrice,
          lineInput.requestedQuantity,
          lineInput.reasonCode,
          lineInput.conditionCode
        );

        if (refundResult.valid != true) {
          return rollbackFailure(
            savepointRecord,
            refundResult.code,
            refundResult.message
          );
        }

        refundResultsByOrderItemId.put(orderItemId, refundResult);

        totalEstimatedRefund += refundResult.refundAmount;
      }

      /*
       * Lấy Order header từ dữ liệu đã lock.
       * Tất cả OrderItem đã được validate thuộc cùng input.orderId.
       */
      OrderItem firstOrderItem = lockedOrderItemsById.values()[0];

      Id customerId = firstOrderItem.Order.AccountId;

      Id storeId = firstOrderItem.Order.Store__c;

      /*
       * Preview Approval Level:
       * Method này không DML.
       */
      String approvalLevel = ApprovalRoutingService.determineRequiredApprovalLevel(
        customerId,
        totalEstimatedRefund
      );

      Return_Request__c requestRecord = new Return_Request__c(
        Order__c = input.orderId,
        Customer__c = customerId,
        Store__c = storeId,
        Status__c = SmartReturnConstants.STATUS_NEW,
        Source_Channel__c = normalizeSourceChannel(input.sourceChannel),
        External_Request_ID__c = input.externalRequestId,
        Estimated_Refund_Amount__c = totalEstimatedRefund,
        Required_Approval_Level__c = approvalLevel
      );

      insert requestRecord;

      List<Return_Request_Line__c> returnLines = new List<Return_Request_Line__c>();

      for (Id orderItemId : orderItemIds) {
        OrderItem orderItem = lockedOrderItemsById.get(orderItemId);

        CreateReturnLineInput lineInput = inputLineByOrderItemId.get(
          orderItemId
        );

        ReturnEligibilityResult eligibilityResult = eligibilityResults.get(
          orderItemId
        );

        ReturnRefundResult refundResult = refundResultsByOrderItemId.get(
          orderItemId
        );

        returnLines.add(
          new Return_Request_Line__c(
            Return_Request__c = requestRecord.Id,
            Order_Item__c = orderItem.Id,
            Product__c = orderItem.Product2Id,
            Purchased_Quantity__c = orderItem.Quantity,
            Requested_Quantity__c = lineInput.requestedQuantity,
            Unit_Price_Paid__c = orderItem.UnitPrice,
            Return_Reason__c = refundResult.reasonCode,
            Reported_Condition__c = refundResult.conditionCode,
            Is_Eligible__c = true,
            Eligibility_Code__c = eligibilityResult.code,
            Eligibility_Reason__c = eligibilityResult.message,
            Return_Deadline__c = eligibilityResult.returnDeadline,
            Estimated_Refund_Rate__c = refundResult.refundRate,
            Estimated_Refund_Amount__c = refundResult.refundAmount
          )
        );
      }

      insert returnLines;

      /*
       * Routing thật sau khi Return Request đã có Id.
       * Method này chuyển NEW sang trạng thái phù hợp.
       */
      ApprovalRoutingService.evaluateInitialStatus(requestRecord);

      /*
       * Query lại vì evaluateInitialStatus đã update
       * Status và Required Approval Level.
       */
      requestRecord = [
        SELECT
          Id,
          Name,
          Status__c,
          Required_Approval_Level__c,
          Estimated_Refund_Amount__c
        FROM Return_Request__c
        WHERE Id = :requestRecord.Id
        LIMIT 1
      ];

      System.debug(
        LoggingLevel.INFO,
        'REQ-04 | Return Request created' +
          ' | requestId=' +
          requestRecord.Id +
          ' | requestNumber=' +
          requestRecord.Name +
          ' | status=' +
          requestRecord.Status__c +
          ' | approvalLevel=' +
          requestRecord.Required_Approval_Level__c +
          ' | estimatedRefund=' +
          requestRecord.Estimated_Refund_Amount__c +
          ' | lineCount=' +
          returnLines.size()
      );

      return CreateReturnResult.success(requestRecord);
    } catch (Exception exceptionRecord) {
      Database.rollback(savepointRecord);

      System.debug(
        LoggingLevel.ERROR,
        'REQ-04 | Create Return failed' +
          ' | exceptionType=' +
          exceptionRecord.getTypeName() +
          ' | message=' +
          exceptionRecord.getMessage() +
          ' | stackTrace=' +
          exceptionRecord.getStackTraceString()
      );

      return CreateReturnResult.failure(
        'CREATE_RETURN_FAILED',
        exceptionRecord.getMessage()
      );
    }
  }

  private static void validateInput(CreateReturnInput input) {
    if (input == null) {
      throw new ReturnIntakeException(
        'Dữ liệu tạo yêu cầu không được để trống.'
      );
    }

    if (input.orderId == null) {
      throw new ReturnIntakeException('Đơn hàng không được để trống.');
    }

    if (input.lines == null || input.lines.isEmpty()) {
      throw new ReturnIntakeException('Phải chọn ít nhất một sản phẩm để trả.');
    }

    Boolean hasPositiveQuantity = false;

    for (CreateReturnLineInput lineInput : input.lines) {
      if (lineInput == null) {
        throw new ReturnIntakeException('Dòng sản phẩm không hợp lệ.');
      }

      if (lineInput.orderItemId == null) {
        throw new ReturnIntakeException('Order Item không được để trống.');
      }

      if (
        lineInput.requestedQuantity != null &&
        lineInput.requestedQuantity > 0
      ) {
        hasPositiveQuantity = true;
      }

      if (String.isBlank(lineInput.reasonCode)) {
        throw new ReturnIntakeException('Lý do trả hàng không được để trống.');
      }

      if (String.isBlank(lineInput.conditionCode)) {
        throw new ReturnIntakeException(
          'Tình trạng sản phẩm không được để trống.'
        );
      }
    }

    if (!hasPositiveQuantity) {
      throw new ReturnIntakeException(
        'Phải có ít nhất một dòng có số lượng trả lớn hơn 0.'
      );
    }
  }

  private static Map<Id, CreateReturnLineInput> buildInputLineMap(
    List<CreateReturnLineInput> inputLines
  ) {
    Map<Id, CreateReturnLineInput> inputLineByOrderItemId = new Map<Id, CreateReturnLineInput>();

    for (CreateReturnLineInput lineInput : inputLines) {
      if (inputLineByOrderItemId.containsKey(lineInput.orderItemId)) {
        throw new ReturnIntakeException(
          'Một sản phẩm không được xuất hiện nhiều lần trong cùng yêu cầu.'
        );
      }

      inputLineByOrderItemId.put(lineInput.orderItemId, lineInput);
    }

    return inputLineByOrderItemId;
  }

  private static String normalizeSourceChannel(String sourceChannel) {
    if (String.isBlank(sourceChannel)) {
      return SmartReturnConstants.SOURCE_STORE;
    }

    String normalizedChannel = sourceChannel.trim().toUpperCase();

    Set<String> allowedChannels = new Set<String>{
      SmartReturnConstants.SOURCE_STORE,
      SmartReturnConstants.SOURCE_POS,
      SmartReturnConstants.SOURCE_APP,
      SmartReturnConstants.SOURCE_MIGRATION
    };

    if (!allowedChannels.contains(normalizedChannel)) {
      throw new ReturnIntakeException('Source Channel không hợp lệ.');
    }

    return normalizedChannel;
  }

  private static CreateReturnResult rollbackFailure(
    Savepoint savepointRecord,
    String code,
    String message
  ) {
    Database.rollback(savepointRecord);

    System.debug(
      LoggingLevel.WARN,
      'REQ-04 | Validation failed' + ' | code=' + code + ' | message=' + message
    );

    return CreateReturnResult.failure(code, message);
  }
}
