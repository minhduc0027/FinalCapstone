@IsTest
private class ReturnQuantityServiceTests {
  private static PricebookEntry createPricebookEntry(
    String productCode,
    Decimal unitPrice
  ) {
    Product2 product = new Product2(
      Name = 'REQ-06 Product ' + productCode,
      ProductCode = productCode,
      Family = 'Laptop',
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

    return pricebookEntry;
  }

  private static OrderItem createOrderItem(
    String productCode,
    Decimal purchasedQuantity
  ) {
    Account customer = new Account(
      Name = 'REQ-06 Test Customer ' + productCode
    );
    insert customer;

    Store__c store = new Store__c(
      Store_Code__c = 'REQ06-' +
        String.valueOf(Math.abs(Crypto.getRandomInteger())).left(10)
    );
    insert store;

    Order orderRecord = new Order(
      AccountId = customer.Id,
      Store__c = store.Id,
      EffectiveDate = Date.today(),
      Delivery_Date__c = Date.today(),
      Status = 'Draft',
      Pricebook2Id = Test.getStandardPricebookId()
    );
    insert orderRecord;

    PricebookEntry pricebookEntry = createPricebookEntry(productCode, 1000000);

    OrderItem orderItem = new OrderItem(
      OrderId = orderRecord.Id,
      PricebookEntryId = pricebookEntry.Id,
      Quantity = purchasedQuantity,
      UnitPrice = pricebookEntry.UnitPrice
    );
    insert orderItem;

    return orderItem;
  }

  private static Return_Request__c createReturnRequest(
    OrderItem orderItem,
    String status
  ) {
    OrderItem populatedOrderItem = [
      SELECT Id, OrderId, Order.AccountId, Order.Store__c
      FROM OrderItem
      WHERE Id = :orderItem.Id
      LIMIT 1
    ];

    Return_Request__c returnRequest = new Return_Request__c(
      Order__c = populatedOrderItem.OrderId,
      Customer__c = populatedOrderItem.Order.AccountId,
      Store__c = populatedOrderItem.Order.Store__c,
      Status__c = status,
      Source_Channel__c = 'STORE',
      Estimated_Refund_Amount__c = 0
    );

    insert returnRequest;

    System.debug(
      LoggingLevel.INFO,
      'TEST REQ-06 | Created Return Request' +
        ' | requestId=' +
        returnRequest.Id +
        ' | orderId=' +
        returnRequest.Order__c +
        ' | storeId=' +
        returnRequest.Store__c +
        ' | status=' +
        returnRequest.Status__c
    );

    return returnRequest;
  }

  private static void createReturnLine(
    Return_Request__c returnRequest,
    OrderItem orderItem,
    Decimal requestedQuantity
  ) {
    Return_Request_Line__c returnLine = new Return_Request_Line__c(
      Return_Request__c = returnRequest.Id,
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

  private static void debugResult(
    String scenario,
    ReturnQuantityResult result
  ) {
    System.debug(
      LoggingLevel.INFO,
      'TEST REQ-06 | ' +
        scenario +
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

  @IsTest
  static void evaluate_ShouldBeValid_WhenNoPreviousReturn() {
    OrderItem orderItem = createOrderItem('NO-PREVIOUS-RETURN', 5);

    Test.startTest();

    Map<Id, ReturnQuantityResult> results = ReturnQuantityService.evaluate(
      new Map<Id, Decimal>{ orderItem.Id => 3 }
    );

    Test.stopTest();

    ReturnQuantityResult result = results.get(orderItem.Id);

    debugResult('NO_PREVIOUS_RETURN', result);

    System.assertEquals(5, result.purchasedQuantity);
    System.assertEquals(0, result.activeReturnedQuantity);
    System.assertEquals(5, result.remainingQuantity);
    System.assertEquals(true, result.valid);
    System.assertEquals('QUANTITY_AVAILABLE', result.code);
  }

  @IsTest
  static void evaluate_ShouldSubtractActiveReturnQuantity() {
    OrderItem orderItem = createOrderItem('ACTIVE-RETURN', 5);

    Return_Request__c existingRequest = createReturnRequest(
      orderItem,
      StateTransitionService.STATUS_NEW
    );

    createReturnLine(existingRequest, orderItem, 2);

    Test.startTest();

    Map<Id, ReturnQuantityResult> results = ReturnQuantityService.evaluate(
      new Map<Id, Decimal>{ orderItem.Id => 3 }
    );

    Test.stopTest();

    ReturnQuantityResult result = results.get(orderItem.Id);

    debugResult('ACTIVE_RETURN', result);

    System.assertEquals(5, result.purchasedQuantity);
    System.assertEquals(2, result.activeReturnedQuantity);
    System.assertEquals(3, result.remainingQuantity);
    System.assertEquals(true, result.valid);
    System.assertEquals('QUANTITY_AVAILABLE', result.code);
  }

  @IsTest
  static void evaluate_ShouldReject_WhenQuantityExceeded() {
    OrderItem orderItem = createOrderItem('QUANTITY-EXCEEDED', 5);

    Return_Request__c existingRequest = createReturnRequest(
      orderItem,
      StateTransitionService.STATUS_PENDING_APPROVAL
    );

    createReturnLine(existingRequest, orderItem, 3);

    Test.startTest();

    Map<Id, ReturnQuantityResult> results = ReturnQuantityService.evaluate(
      new Map<Id, Decimal>{ orderItem.Id => 3 }
    );

    Test.stopTest();

    ReturnQuantityResult result = results.get(orderItem.Id);

    debugResult('QUANTITY_EXCEEDED', result);

    System.assertEquals(3, result.activeReturnedQuantity);
    System.assertEquals(2, result.remainingQuantity);
    System.assertEquals(false, result.valid);
    System.assertEquals('QUANTITY_EXCEEDED', result.code);
  }

  @IsTest
  static void evaluate_ShouldIgnoreRejectedAndCancelledRequests() {
    OrderItem orderItem = createOrderItem('IGNORED-STATUSES', 5);

    Return_Request__c rejectedRequest = createReturnRequest(
      orderItem,
      StateTransitionService.STATUS_REJECTED
    );

    Return_Request__c cancelledRequest = createReturnRequest(
      orderItem,
      StateTransitionService.STATUS_CANCELLED
    );

    createReturnLine(rejectedRequest, orderItem, 2);

    createReturnLine(cancelledRequest, orderItem, 2);

    Test.startTest();

    Map<Id, ReturnQuantityResult> results = ReturnQuantityService.evaluate(
      new Map<Id, Decimal>{ orderItem.Id => 5 }
    );

    Test.stopTest();

    ReturnQuantityResult result = results.get(orderItem.Id);

    debugResult('IGNORE_REJECTED_CANCELLED', result);

    System.assertEquals(
      0,
      result.activeReturnedQuantity,
      'REJECTED và CANCELLED không được chiếm quantity'
    );

    System.assertEquals(5, result.remainingQuantity);
    System.assertEquals(true, result.valid);
  }

  @IsTest
  static void evaluate_ShouldCountCompletedAndRefundFailed() {
    OrderItem orderItem = createOrderItem('FINAL-STATUSES', 5);

    Return_Request__c completedRequest = createReturnRequest(
      orderItem,
      StateTransitionService.STATUS_COMPLETED
    );

    Return_Request__c refundFailedRequest = createReturnRequest(
      orderItem,
      StateTransitionService.STATUS_REFUND_FAILED
    );

    createReturnLine(completedRequest, orderItem, 2);

    createReturnLine(refundFailedRequest, orderItem, 1);

    Test.startTest();

    Map<Id, ReturnQuantityResult> results = ReturnQuantityService.evaluate(
      new Map<Id, Decimal>{ orderItem.Id => 2 }
    );

    Test.stopTest();

    ReturnQuantityResult result = results.get(orderItem.Id);

    debugResult('COUNT_COMPLETED_REFUND_FAILED', result);

    System.assertEquals(3, result.activeReturnedQuantity);
    System.assertEquals(2, result.remainingQuantity);
    System.assertEquals(true, result.valid);
  }

  @IsTest
  static void evaluate_ShouldRejectInvalidRequestedQuantity() {
    OrderItem orderItem = createOrderItem('INVALID-QUANTITY', 5);

    Test.startTest();

    Map<Id, ReturnQuantityResult> results = ReturnQuantityService.evaluate(
      new Map<Id, Decimal>{ orderItem.Id => 0 }
    );

    Test.stopTest();

    ReturnQuantityResult result = results.get(orderItem.Id);

    debugResult('INVALID_REQUESTED_QUANTITY', result);

    System.assertEquals(false, result.valid);
    System.assertEquals('INVALID_REQUESTED_QUANTITY', result.code);
  }

  @IsTest
  static void evaluate_ShouldReturnEmpty_WhenInputEmpty() {
    Test.startTest();

    Map<Id, ReturnQuantityResult> results = ReturnQuantityService.evaluate(
      new Map<Id, Decimal>()
    );

    Test.stopTest();

    System.debug(
      LoggingLevel.INFO,
      'TEST REQ-06 | EMPTY_INPUT' + ' | resultCount=' + results.size()
    );

    System.assertEquals(0, results.size());
  }
}
