@IsTest
private class ReturnIntakeServiceTests {
  private static Integer sequenceNumber = 0;

  // =========================================================
  // TEST DATA HELPERS
  // =========================================================

  private static String nextCode(String prefix) {
    sequenceNumber++;

    return prefix + '-' + String.valueOf(sequenceNumber);
  }

  private static Store__c createStore() {
    Store__c store = new Store__c(Store_Code__c = nextCode('STORE'));
    insert store;

    return store;
  }

  private static Account createCustomer() {
    Account customer = new Account(Name = nextCode('REQ-04 Customer'));
    insert customer;

    return customer;
  }

  private static Product2 createProduct(String family) {
    String productCode = nextCode('PRODUCT');

    Product2 product = new Product2(
      Name = productCode,
      ProductCode = productCode,
      Family = family,
      IsActive = true
    );
    insert product;

    return product;
  }

  private static PricebookEntry createPricebookEntry(
    Product2 product,
    Decimal unitPrice
  ) {
    PricebookEntry pricebookEntry = new PricebookEntry(
      Pricebook2Id = Test.getStandardPricebookId(),
      Product2Id = product.Id,
      UnitPrice = unitPrice,
      IsActive = true
    );
    insert pricebookEntry;

    return pricebookEntry;
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
    String family,
    Decimal purchasedQuantity,
    Decimal unitPrice
  ) {
    Product2 product = createProduct(family);

    PricebookEntry pricebookEntry = createPricebookEntry(product, unitPrice);

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
    CreateReturnLineInput lineInput = new CreateReturnLineInput();

    lineInput.orderItemId = orderItemId;
    lineInput.requestedQuantity = requestedQuantity;
    lineInput.reasonCode = reasonCode;
    lineInput.conditionCode = conditionCode;

    return lineInput;
  }

  private static CreateReturnInput createInput(
    Id orderId,
    List<CreateReturnLineInput> lines
  ) {
    CreateReturnInput input = new CreateReturnInput();

    input.orderId = orderId;
    input.sourceChannel = SmartReturnConstants.SOURCE_STORE;
    input.externalRequestId = null;
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
    Return_Request_Line__c returnLine = new Return_Request_Line__c(
      Return_Request__c = requestRecord.Id,
      Order_Item__c = orderItem.Id,
      Product__c = orderItem.Product2Id,
      Purchased_Quantity__c = orderItem.Quantity,
      Requested_Quantity__c = requestedQuantity,
      Unit_Price_Paid__c = orderItem.UnitPrice,
      Return_Reason__c = 'DEFECT',
      Reported_Condition__c = 'SEALED',
      Is_Eligible__c = true,
      Eligibility_Code__c = 'ELIGIBLE',
      Estimated_Refund_Rate__c = 100,
      Estimated_Refund_Amount__c = orderItem.UnitPrice * requestedQuantity
    );

    insert returnLine;
  }

  private static void debugResult(String scenario, CreateReturnResult result) {
    System.debug(
      LoggingLevel.INFO,
      'TEST REQ-04 | ' +
        scenario +
        ' | success=' +
        result.success +
        ' | requestId=' +
        result.returnRequestId +
        ' | requestNumber=' +
        result.returnRequestNumber +
        ' | status=' +
        result.status +
        ' | approvalLevel=' +
        result.approvalLevel +
        ' | estimatedRefund=' +
        result.estimatedRefundAmount +
        ' | code=' +
        result.code +
        ' | message=' +
        result.message
    );
  }

  // =========================================================
  // TEST 1: HAPPY PATH - ONE LINE
  // =========================================================

  @IsTest
  static void createReturn_ShouldCreateRequestAndLine() {
    Store__c store = createStore();
    Account customer = createCustomer();

    Order orderRecord = createOrder(customer, store, Date.today());

    OrderItem orderItem = createOrderItem(orderRecord, 'Laptop', 5, 1000000);

    CreateReturnInput input = createInput(
      orderRecord.Id,
      new List<CreateReturnLineInput>{
        createLineInput(orderItem.Id, 2, 'DEFECT', 'SEALED')
      }
    );

    Test.startTest();

    CreateReturnResult result = ReturnIntakeService.createReturn(input);

    Test.stopTest();

    debugResult('HAPPY_PATH_ONE_LINE', result);

    System.assertEquals(true, result.success);
    System.assertEquals('RETURN_REQUEST_CREATED', result.code);
    System.assertNotEquals(null, result.returnRequestId);
    System.assertNotEquals(null, result.approvalLevel);

    Return_Request__c actualRequest = [
      SELECT
        Id,
        Name,
        Order__c,
        Customer__c,
        Store__c,
        Status__c,
        Source_Channel__c,
        Required_Approval_Level__c,
        Estimated_Refund_Amount__c
      FROM Return_Request__c
      WHERE Id = :result.returnRequestId
    ];

    System.assertEquals(orderRecord.Id, actualRequest.Order__c);
    System.assertEquals(customer.Id, actualRequest.Customer__c);
    System.assertEquals(store.Id, actualRequest.Store__c);
    System.assertEquals(
      SmartReturnConstants.SOURCE_STORE,
      actualRequest.Source_Channel__c
    );
    System.assertEquals(2000000, actualRequest.Estimated_Refund_Amount__c);
    System.assertNotEquals(
      SmartReturnConstants.STATUS_NEW,
      actualRequest.Status__c,
      'Request phải được initial routing sau khi tạo'
    );

    List<Return_Request_Line__c> actualLines = [
      SELECT
        Return_Request__c,
        Order_Item__c,
        Product__c,
        Purchased_Quantity__c,
        Requested_Quantity__c,
        Unit_Price_Paid__c,
        Return_Reason__c,
        Reported_Condition__c,
        Is_Eligible__c,
        Eligibility_Code__c,
        Estimated_Refund_Rate__c,
        Estimated_Refund_Amount__c
      FROM Return_Request_Line__c
      WHERE Return_Request__c = :actualRequest.Id
    ];

    System.assertEquals(1, actualLines.size());

    Return_Request_Line__c actualLine = actualLines[0];

    System.assertEquals(orderItem.Id, actualLine.Order_Item__c);
    OrderItem populatedOrderItem = [
      SELECT Id, Product2Id, Quantity, UnitPrice
      FROM OrderItem
      WHERE Id = :orderItem.Id
      LIMIT 1
    ];

    System.assertEquals(
      populatedOrderItem.Product2Id,
      actualLine.Product__c,
      'Return Line phải tham chiếu đúng Product của Order Item'
    );

    System.assertEquals(5, actualLine.Purchased_Quantity__c);
    System.assertEquals(2, actualLine.Requested_Quantity__c);
    System.assertEquals(100, actualLine.Estimated_Refund_Rate__c);
    System.assertEquals(2000000, actualLine.Estimated_Refund_Amount__c);
    System.assertEquals('ELIGIBLE', actualLine.Eligibility_Code__c);
  }

  // =========================================================
  // TEST 2: MULTIPLE LINES
  // =========================================================

  @IsTest
  static void createReturn_ShouldCreateMultipleLinesAndTotal() {
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

    CreateReturnInput input = createInput(
      orderRecord.Id,
      new List<CreateReturnLineInput>{
        createLineInput(laptopItem.Id, 2, 'DEFECT', 'SEALED'),
        createLineInput(accessoryItem.Id, 1, 'NOT_SATISFIED', 'OPENED')
      }
    );

    Test.startTest();

    CreateReturnResult result = ReturnIntakeService.createReturn(input);

    Test.stopTest();

    debugResult('MULTIPLE_LINES', result);

    /*
     * Laptop:
     * 1.000.000 × 2 × 100% = 2.000.000
     *
     * Accessory:
     * 500.000 × 1 × 80% = 400.000
     *
     * Total = 2.400.000
     */
    System.assertEquals(true, result.success);
    System.assertEquals(2400000, result.estimatedRefundAmount);

    Integer lineCount = [
      SELECT COUNT()
      FROM Return_Request_Line__c
      WHERE Return_Request__c = :result.returnRequestId
    ];

    System.assertEquals(2, lineCount);
  }

  // =========================================================
  // TEST 3: QUANTITY EXCEEDED
  // =========================================================

  @IsTest
  static void createReturn_ShouldRollback_WhenQuantityExceeded() {
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

    Integer requestsBefore = [
      SELECT COUNT()
      FROM Return_Request__c
    ];

    Integer linesBefore = [
      SELECT COUNT()
      FROM Return_Request_Line__c
    ];

    CreateReturnInput input = createInput(
      orderRecord.Id,
      new List<CreateReturnLineInput>{
        createLineInput(orderItem.Id, 2, 'DEFECT', 'SEALED')
      }
    );

    Test.startTest();

    CreateReturnResult result = ReturnIntakeService.createReturn(input);

    Test.stopTest();

    debugResult('QUANTITY_EXCEEDED', result);

    System.assertEquals(false, result.success);
    System.assertEquals('QUANTITY_EXCEEDED', result.code);

    System.assertEquals(
      requestsBefore,
      [
        SELECT COUNT()
        FROM Return_Request__c
      ]
    );

    System.assertEquals(
      linesBefore,
      [
        SELECT COUNT()
        FROM Return_Request_Line__c
      ]
    );
  }

  // =========================================================
  // TEST 4: EXPIRED ITEM
  // =========================================================

  @IsTest
  static void createReturn_ShouldRollback_WhenItemExpired() {
    Store__c store = createStore();
    Account customer = createCustomer();

    Order orderRecord = createOrder(customer, store, Date.today().addDays(-30));

    OrderItem orderItem = createOrderItem(orderRecord, 'Laptop', 2, 1000000);

    CreateReturnInput input = createInput(
      orderRecord.Id,
      new List<CreateReturnLineInput>{
        createLineInput(orderItem.Id, 1, 'DEFECT', 'SEALED')
      }
    );

    Test.startTest();

    CreateReturnResult result = ReturnIntakeService.createReturn(input);

    Test.stopTest();

    debugResult('RETURN_PERIOD_EXPIRED', result);

    System.assertEquals(false, result.success);
    System.assertEquals('RETURN_PERIOD_EXPIRED', result.code);

    System.assertEquals(
      0,
      [
        SELECT COUNT()
        FROM Return_Request__c
        WHERE Order__c = :orderRecord.Id
      ]
    );
  }

  // =========================================================
  // TEST 5: REFUND RATE ZERO
  // =========================================================

  @IsTest
  static void createReturn_ShouldRollback_WhenRefundRateZero() {
    Store__c store = createStore();
    Account customer = createCustomer();

    Order orderRecord = createOrder(customer, store, Date.today());

    OrderItem orderItem = createOrderItem(orderRecord, 'Laptop', 2, 1000000);

    CreateReturnInput input = createInput(
      orderRecord.Id,
      new List<CreateReturnLineInput>{
        createLineInput(orderItem.Id, 1, 'CUSTOMER_DAMAGED', 'SEALED')
      }
    );

    Test.startTest();

    CreateReturnResult result = ReturnIntakeService.createReturn(input);

    Test.stopTest();

    debugResult('REFUND_RATE_ZERO', result);

    System.assertEquals(false, result.success);
    System.assertEquals('REFUND_RATE_ZERO', result.code);

    System.assertEquals(
      0,
      [
        SELECT COUNT()
        FROM Return_Request__c
        WHERE Order__c = :orderRecord.Id
      ]
    );
  }

  // =========================================================
  // TEST 6: ORDER ITEM BELONGS TO ANOTHER ORDER
  // =========================================================

  @IsTest
  static void createReturn_ShouldRejectOrderItemFromAnotherOrder() {
    Store__c store = createStore();
    Account customer = createCustomer();

    Order orderA = createOrder(customer, store, Date.today());

    Order orderB = createOrder(customer, store, Date.today());

    OrderItem itemFromOrderB = createOrderItem(orderB, 'Laptop', 2, 1000000);

    CreateReturnInput input = createInput(
      orderA.Id,
      new List<CreateReturnLineInput>{
        createLineInput(itemFromOrderB.Id, 1, 'DEFECT', 'SEALED')
      }
    );

    Test.startTest();

    CreateReturnResult result = ReturnIntakeService.createReturn(input);

    Test.stopTest();

    debugResult('ORDER_ITEM_FROM_ANOTHER_ORDER', result);

    System.assertEquals(false, result.success);
    System.assertEquals('INVALID_ORDER_ITEM', result.code);
  }

  // =========================================================
  // TEST 7: DUPLICATE ORDER ITEM INPUT
  // =========================================================

  @IsTest
  static void createReturn_ShouldRejectDuplicateOrderItem() {
    Store__c store = createStore();
    Account customer = createCustomer();

    Order orderRecord = createOrder(customer, store, Date.today());

    OrderItem orderItem = createOrderItem(orderRecord, 'Laptop', 5, 1000000);

    CreateReturnLineInput duplicateLineOne = createLineInput(
      orderItem.Id,
      1,
      'DEFECT',
      'SEALED'
    );

    CreateReturnLineInput duplicateLineTwo = createLineInput(
      orderItem.Id,
      1,
      'DEFECT',
      'SEALED'
    );

    CreateReturnInput input = createInput(
      orderRecord.Id,
      new List<CreateReturnLineInput>{ duplicateLineOne, duplicateLineTwo }
    );

    Test.startTest();

    CreateReturnResult result = ReturnIntakeService.createReturn(input);

    Test.stopTest();

    debugResult('DUPLICATE_ORDER_ITEM', result);

    System.assertEquals(false, result.success);
    System.assertEquals('CREATE_RETURN_FAILED', result.code);
    System.assert(result.message.contains('không được xuất hiện nhiều lần'));
  }

  // =========================================================
  // TEST 8: MIXED VALID AND INVALID LINES ROLLBACK EVERYTHING
  // =========================================================

  @IsTest
  static void createReturn_ShouldRollbackAll_WhenOneLineInvalid() {
    Store__c store = createStore();
    Account customer = createCustomer();

    Order orderRecord = createOrder(customer, store, Date.today());

    OrderItem validItem = createOrderItem(orderRecord, 'Laptop', 5, 1000000);

    OrderItem invalidItem = createOrderItem(
      orderRecord,
      'Phần Mềm',
      1,
      2000000
    );

    CreateReturnInput input = createInput(
      orderRecord.Id,
      new List<CreateReturnLineInput>{
        createLineInput(validItem.Id, 1, 'DEFECT', 'SEALED'),
        createLineInput(invalidItem.Id, 1, 'DEFECT', 'SEALED')
      }
    );

    Test.startTest();

    CreateReturnResult result = ReturnIntakeService.createReturn(input);

    Test.stopTest();

    debugResult('ROLLBACK_MIXED_LINES', result);

    System.assertEquals(false, result.success);
    System.assertEquals('CATEGORY_NOT_RETURNABLE', result.code);

    System.assertEquals(
      0,
      [
        SELECT COUNT()
        FROM Return_Request__c
        WHERE Order__c = :orderRecord.Id
      ],
      'Một line sai thì không được tạo header'
    );

    System.assertEquals(
      0,
      [
        SELECT COUNT()
        FROM Return_Request_Line__c
        WHERE Order_Item__c IN :new Set<Id>{ validItem.Id, invalidItem.Id }
      ],
      'Một line sai thì không được tạo bất kỳ line nào'
    );
  }
}
