@IsTest
private class ReturnPreviewServiceTests {
  private static Integer sequenceNumber = 0;

  // =========================================================
  // TEST DATA
  // =========================================================

  private static String nextCode(String prefix) {
    sequenceNumber++;

    return prefix + '-' + String.valueOf(sequenceNumber);
  }

  private static Store__c createStore() {
    Store__c store = new Store__c(Store_Code__c = nextCode('PREVIEW-STORE'));
    insert store;

    return store;
  }

  private static Account createCustomer() {
    Account customer = new Account(
      Name = nextCode('Preview Customer'),
      Phone = '0900000000'
    );
    insert customer;

    return customer;
  }

  private static Order createOrder(
    Account customer,
    Store__c store,
    Date deliveryDate
  ) {
    Order orderRecord = new Order(
      AccountId = customer.Id,
      Store__c = store.Id,
      EffectiveDate = Date.today(),
      Delivery_Date__c = deliveryDate,
      Status = 'Draft',
      Pricebook2Id = Test.getStandardPricebookId()
    );
    insert orderRecord;

    return orderRecord;
  }

  private static OrderItem createOrderItem(
    Order orderRecord,
    String productFamily,
    Decimal purchasedQuantity,
    Decimal unitPrice
  ) {
    String productCode = nextCode('PRODUCT');

    Product2 product = new Product2(
      Name = productCode,
      ProductCode = productCode,
      Family = productFamily,
      IsActive = true
    );
    insert product;

    PricebookEntry pricebookEntry = new PricebookEntry(
      Pricebook2Id = Test.getStandardPricebookId(),
      Product2Id = product.Id,
      UnitPrice = unitPrice,
      IsActive = true
    );
    insert pricebookEntry;

    OrderItem orderItem = new OrderItem(
      OrderId = orderRecord.Id,
      PricebookEntryId = pricebookEntry.Id,
      Quantity = purchasedQuantity,
      UnitPrice = unitPrice
    );
    insert orderItem;

    return orderItem;
  }

  private static CreateReturnLineInput createLineInput(
    Id orderItemId,
    Decimal requestedQuantity,
    String reasonCode,
    String conditionCode
  ) {
    CreateReturnLineInput input = new CreateReturnLineInput();

    input.orderItemId = orderItemId;
    input.requestedQuantity = requestedQuantity;
    input.reasonCode = reasonCode;
    input.conditionCode = conditionCode;

    return input;
  }

  private static CreateReturnInput createPreviewInput(
    Id orderId,
    List<CreateReturnLineInput> lines
  ) {
    CreateReturnInput input = new CreateReturnInput();

    input.orderId = orderId;
    input.sourceChannel = SmartReturnConstants.SOURCE_STORE;
    input.lines = lines;

    return input;
  }

  private static Return_Request__c createExistingRequest(
    Order orderRecord,
    Account customer,
    Store__c store,
    String status
  ) {
    Return_Request__c requestRecord = new Return_Request__c(
      Order__c = orderRecord.Id,
      Customer__c = customer.Id,
      Store__c = store.Id,
      Status__c = status,
      Source_Channel__c = SmartReturnConstants.SOURCE_STORE,
      Estimated_Refund_Amount__c = 0
    );

    insert requestRecord;

    return requestRecord;
  }

  private static void createExistingReturnLine(
    Return_Request__c requestRecord,
    OrderItem orderItem,
    Decimal requestedQuantity
  ) {
    OrderItem populatedOrderItem = [
      SELECT Id, Product2Id, Quantity, UnitPrice
      FROM OrderItem
      WHERE Id = :orderItem.Id
      LIMIT 1
    ];

    Return_Request_Line__c returnLine = new Return_Request_Line__c(
      Return_Request__c = requestRecord.Id,
      Order_Item__c = populatedOrderItem.Id,
      Product__c = populatedOrderItem.Product2Id,
      Purchased_Quantity__c = populatedOrderItem.Quantity,
      Requested_Quantity__c = requestedQuantity,
      Unit_Price_Paid__c = populatedOrderItem.UnitPrice,
      Return_Reason__c = 'DEFECT',
      Reported_Condition__c = 'SEALED',
      Is_Eligible__c = true,
      Eligibility_Code__c = 'ELIGIBLE',
      Estimated_Refund_Rate__c = 100,
      Estimated_Refund_Amount__c = populatedOrderItem.UnitPrice *
        requestedQuantity
    );

    insert returnLine;
  }

  private static CreateReturnOrderLine findLine(
    List<CreateReturnOrderLine> lines,
    Id orderItemId
  ) {
    for (CreateReturnOrderLine line : lines) {
      if (line.orderItemId == orderItemId) {
        return line;
      }
    }

    return null;
  }

  private static void debugPageResult(
    String scenario,
    CreateReturnPageResult result
  ) {
    System.debug(
      LoggingLevel.INFO,
      'TEST REQ-04 PREVIEW | ' +
        scenario +
        ' | success=' +
        result.success +
        ' | lineCount=' +
        (result.lines == null ? 0 : result.lines.size()) +
        ' | totalEstimatedRefund=' +
        result.totalEstimatedRefund +
        ' | approvalLevel=' +
        result.approvalLevel +
        ' | canSubmit=' +
        result.canSubmit +
        ' | code=' +
        result.code +
        ' | message=' +
        result.message
    );

    if (result.lines == null) {
      return;
    }

    for (CreateReturnOrderLine line : result.lines) {
      System.debug(
        LoggingLevel.INFO,
        'TEST REQ-04 PREVIEW LINE' +
          ' | orderItemId=' +
          line.orderItemId +
          ' | product=' +
          line.productName +
          ' | eligible=' +
          line.eligible +
          ' | purchased=' +
          line.purchasedQuantity +
          ' | activeReturned=' +
          line.activeReturnedQuantity +
          ' | remaining=' +
          line.remainingQuantity +
          ' | requested=' +
          line.requestedQuantity +
          ' | refundRate=' +
          line.refundRate +
          ' | refundAmount=' +
          line.estimatedRefundAmount +
          ' | valid=' +
          line.valid +
          ' | validationMessage=' +
          line.validationMessage
      );
    }
  }

  // =========================================================
  // TEST 1: LOAD CREATE RETURN PAGE
  // =========================================================

  @IsTest
  static void loadCreateReturnPage_ShouldReturnHeaderAndLines() {
    Store__c store = createStore();
    Account customer = createCustomer();

    Order orderRecord = createOrder(customer, store, Date.today());

    OrderItem laptopItem = createOrderItem(orderRecord, 'Laptop', 5, 1000000);

    OrderItem accessoryItem = createOrderItem(
      orderRecord,
      'Phụ Kiện',
      3,
      500000
    );

    Test.startTest();

    CreateReturnPageResult result = ReturnPreviewService.loadCreateReturnPage(
      orderRecord.Id
    );

    Test.stopTest();

    debugPageResult('LOAD_PAGE', result);

    System.assertEquals(true, result.success);
    System.assertEquals('CREATE_RETURN_PAGE_LOADED', result.code);

    System.assertNotEquals(null, result.header);
    System.assertEquals(orderRecord.Id, result.header.orderId);
    System.assertEquals(customer.Id, result.header.customerId);
    System.assertEquals(customer.Name, result.header.customerName);
    System.assertEquals(customer.Phone, result.header.customerPhone);
    System.assertEquals(store.Id, result.header.storeId);
    System.assertEquals(store.Store_Code__c, result.header.storeCode);

    System.assertEquals(2, result.lines.size());
    System.assertEquals(0, result.totalEstimatedRefund);
    System.assertEquals(null, result.approvalLevel);
    System.assertEquals(false, result.canSubmit);

    CreateReturnOrderLine laptopLine = findLine(result.lines, laptopItem.Id);

    CreateReturnOrderLine accessoryLine = findLine(
      result.lines,
      accessoryItem.Id
    );

    System.assertNotEquals(null, laptopLine);
    System.assertNotEquals(null, accessoryLine);

    System.assertEquals(true, laptopLine.eligible);
    System.assertEquals(5, laptopLine.purchasedQuantity);
    System.assertEquals(0, laptopLine.activeReturnedQuantity);
    System.assertEquals(5, laptopLine.remainingQuantity);
    System.assertEquals(0, laptopLine.requestedQuantity);

    System.assertEquals(true, accessoryLine.eligible);
    System.assertEquals(3, accessoryLine.remainingQuantity);
  }

  // =========================================================
  // TEST 2: VALID MULTI-LINE PREVIEW
  // =========================================================

  @IsTest
  static void previewReturn_ShouldCalculateRefundAndApproval() {
    Store__c store = createStore();
    Account customer = createCustomer();

    Order orderRecord = createOrder(customer, store, Date.today());

    OrderItem laptopItem = createOrderItem(orderRecord, 'Laptop', 5, 1000000);

    OrderItem accessoryItem = createOrderItem(
      orderRecord,
      'Phụ Kiện',
      3,
      500000
    );

    CreateReturnInput input = createPreviewInput(
      orderRecord.Id,
      new List<CreateReturnLineInput>{
        createLineInput(laptopItem.Id, 2, 'DEFECT', 'SEALED'),
        createLineInput(accessoryItem.Id, 1, 'NOT_SATISFIED', 'OPENED')
      }
    );

    Test.startTest();

    CreateReturnPageResult result = ReturnPreviewService.previewReturn(input);

    Test.stopTest();

    debugPageResult('VALID_MULTIPLE_LINES', result);

    System.assertEquals(true, result.success);
    System.assertEquals('RETURN_PREVIEW_CALCULATED', result.code);
    System.assertEquals(true, result.canSubmit);

    /*
     * Laptop:
     * 1.000.000 x 2 x 100% = 2.000.000
     *
     * Accessory:
     * 500.000 x 1 x 80% = 400.000
     *
     * Total = 2.400.000
     */
    System.assertEquals(2400000, result.totalEstimatedRefund);

    System.assertEquals(
      SmartReturnConstants.APPROVAL_CHT,
      result.approvalLevel,
      '2,4 triệu phải vượt AUTO và thuộc cấp CHT'
    );

    CreateReturnOrderLine laptopLine = findLine(result.lines, laptopItem.Id);

    CreateReturnOrderLine accessoryLine = findLine(
      result.lines,
      accessoryItem.Id
    );

    System.assertEquals(true, laptopLine.valid);
    System.assertEquals(100, laptopLine.refundRate);
    System.assertEquals(2000000, laptopLine.estimatedRefundAmount);

    System.assertEquals(true, accessoryLine.valid);
    System.assertEquals(80, accessoryLine.refundRate);
    System.assertEquals(400000, accessoryLine.estimatedRefundAmount);
  }

  // =========================================================
  // TEST 3: MISSING REASON OR CONDITION
  // =========================================================

  @IsTest
  static void previewReturn_ShouldDisableSubmit_WhenReasonMissing() {
    Store__c store = createStore();
    Account customer = createCustomer();

    Order orderRecord = createOrder(customer, store, Date.today());

    OrderItem orderItem = createOrderItem(orderRecord, 'Laptop', 5, 1000000);

    CreateReturnInput input = createPreviewInput(
      orderRecord.Id,
      new List<CreateReturnLineInput>{
        createLineInput(orderItem.Id, 1, null, 'SEALED')
      }
    );

    Test.startTest();

    CreateReturnPageResult result = ReturnPreviewService.previewReturn(input);

    Test.stopTest();

    debugPageResult('MISSING_REASON', result);

    System.assertEquals(true, result.success);
    System.assertEquals(false, result.canSubmit);
    System.assertEquals(0, result.totalEstimatedRefund);
    System.assertEquals(null, result.approvalLevel);

    CreateReturnOrderLine previewLine = findLine(result.lines, orderItem.Id);

    System.assertNotEquals(null, previewLine);
    System.assertEquals(false, previewLine.valid);
    System.assert(previewLine.validationMessage.contains('lý do'));
  }

  // =========================================================
  // TEST 4: REQUESTED QUANTITY EXCEEDS REMAINING
  // =========================================================

  @IsTest
  static void previewReturn_ShouldDisableSubmit_WhenQuantityExceeded() {
    Store__c store = createStore();
    Account customer = createCustomer();

    Order orderRecord = createOrder(customer, store, Date.today());

    OrderItem orderItem = createOrderItem(orderRecord, 'Laptop', 5, 1000000);

    Return_Request__c existingRequest = createExistingRequest(
      orderRecord,
      customer,
      store,
      SmartReturnConstants.STATUS_PENDING_APPROVAL
    );

    createExistingReturnLine(existingRequest, orderItem, 4);

    CreateReturnInput input = createPreviewInput(
      orderRecord.Id,
      new List<CreateReturnLineInput>{
        createLineInput(orderItem.Id, 2, 'DEFECT', 'SEALED')
      }
    );

    Test.startTest();

    CreateReturnPageResult result = ReturnPreviewService.previewReturn(input);

    Test.stopTest();

    debugPageResult('QUANTITY_EXCEEDED', result);

    System.assertEquals(true, result.success);
    System.assertEquals(false, result.canSubmit);
    System.assertEquals(0, result.totalEstimatedRefund);

    CreateReturnOrderLine previewLine = findLine(result.lines, orderItem.Id);

    System.assertNotEquals(null, previewLine);
    System.assertEquals(5, previewLine.purchasedQuantity);
    System.assertEquals(4, previewLine.activeReturnedQuantity);
    System.assertEquals(1, previewLine.remainingQuantity);
    System.assertEquals(2, previewLine.requestedQuantity);
    System.assertEquals(false, previewLine.valid);
    System.assert(previewLine.validationMessage.contains('vượt quá'));
  }
}
