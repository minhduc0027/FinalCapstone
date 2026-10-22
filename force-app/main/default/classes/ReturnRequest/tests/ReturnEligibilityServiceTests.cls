@IsTest
private class ReturnEligibilityServiceTests {
  private static PricebookEntry createProductAndPricebookEntry(
    String productName,
    String productCode,
    String productFamily,
    Decimal unitPrice
  ) {
    Product2 product = new Product2(
      Name = productName,
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

    System.debug(
      LoggingLevel.INFO,
      'TEST REQ-05 | Created Product' +
        ' | productId=' +
        product.Id +
        ' | productName=' +
        product.Name +
        ' | family=' +
        product.Family +
        ' | unitPrice=' +
        unitPrice
    );

    return pricebookEntry;
  }

  private static OrderItem createOrderItem(
    PricebookEntry pricebookEntry,
    Date deliveryDate
  ) {
    Store__c store = new Store__c(Store_Code__c = '012345678998765432');
    insert store;

    Account customer = new Account(Name = 'REQ-05 Test Customer');
    insert customer;

    Order orderRecord = new Order(
      AccountId = customer.Id,
      EffectiveDate = Date.today(),
      Delivery_Date__c = deliveryDate,
      Status = 'Draft',
      Pricebook2Id = Test.getStandardPricebookId(),
      Store__c = store.Id
    );
    insert orderRecord;

    OrderItem orderItem = new OrderItem(
      OrderId = orderRecord.Id,
      PricebookEntryId = pricebookEntry.Id,
      Quantity = 2,
      UnitPrice = pricebookEntry.UnitPrice
    );
    insert orderItem;

    System.debug(
      LoggingLevel.INFO,
      'TEST DATA' +
        ' | storeId=' +
        store.Id +
        ' | customerId=' +
        customer.Id +
        ' | orderId=' +
        orderRecord.Id +
        ' | orderItemId=' +
        orderItem.Id +
        ' | deliveryDate=' +
        deliveryDate +
        ' | quantity=' +
        orderItem.Quantity +
        ' | unitPrice=' +
        orderItem.UnitPrice
    );

    return orderItem;
  }

  private static void debugResult(
    String testCase,
    ReturnEligibilityResult result
  ) {
    System.debug(
      LoggingLevel.INFO,
      'TEST REQ-05 | ' +
        testCase +
        ' | orderItemId=' +
        result.orderItemId +
        ' | eligible=' +
        result.eligible +
        ' | code=' +
        result.code +
        ' | message=' +
        result.message +
        ' | returnDeadline=' +
        result.returnDeadline
    );
  }

  @IsTest
  static void evaluate_ShouldReturnEligible_WhenWithinReturnWindow() {
    PricebookEntry pricebookEntry = createProductAndPricebookEntry(
      'Test Laptop',
      'LAPTOP-001',
      'Laptop',
      20000000
    );

    Date deliveryDate = Date.newInstance(2026, 10, 1);
    Date evaluationDate = Date.newInstance(2026, 10, 16);

    OrderItem orderItem = createOrderItem(pricebookEntry, deliveryDate);

    Test.startTest();

    Map<Id, ReturnEligibilityResult> results = ReturnEligibilityService.evaluate(
      new Set<Id>{ orderItem.Id },
      evaluationDate
    );

    Test.stopTest();

    ReturnEligibilityResult result = results.get(orderItem.Id);

    debugResult('WITHIN_RETURN_WINDOW', result);

    System.assertNotEquals(null, result, 'Phải trả về kết quả cho OrderItem');

    System.assertEquals(
      true,
      result.eligible,
      'Laptop ở đúng ngày cuối của thời hạn 15 ngày vẫn hợp lệ'
    );

    System.assertEquals('ELIGIBLE', result.code);

    System.assertEquals(Date.newInstance(2026, 10, 16), result.returnDeadline);
  }

  @IsTest
  static void evaluate_ShouldReturnExpired_WhenPastReturnWindow() {
    PricebookEntry pricebookEntry = createProductAndPricebookEntry(
      'Expired Laptop',
      'LAPTOP-002',
      'Laptop',
      15000000
    );

    OrderItem orderItem = createOrderItem(
      pricebookEntry,
      Date.newInstance(2026, 10, 1)
    );

    Test.startTest();

    Map<Id, ReturnEligibilityResult> results = ReturnEligibilityService.evaluate(
      new Set<Id>{ orderItem.Id },
      Date.newInstance(2026, 10, 17)
    );

    Test.stopTest();

    ReturnEligibilityResult result = results.get(orderItem.Id);

    debugResult('RETURN_PERIOD_EXPIRED', result);

    System.assertEquals(false, result.eligible);

    System.assertEquals('RETURN_PERIOD_EXPIRED', result.code);

    System.assertEquals(Date.newInstance(2026, 10, 16), result.returnDeadline);
  }

  @IsTest
  static void evaluate_ShouldReject_WhenCategoryNotReturnable() {
    PricebookEntry pricebookEntry = createProductAndPricebookEntry(
      'Test Software',
      'SOFTWARE-001',
      'Phần Mềm',
      3000000
    );

    OrderItem orderItem = createOrderItem(
      pricebookEntry,
      Date.newInstance(2026, 10, 20)
    );

    Test.startTest();

    Map<Id, ReturnEligibilityResult> results = ReturnEligibilityService.evaluate(
      new Set<Id>{ orderItem.Id },
      Date.newInstance(2026, 10, 21)
    );

    Test.stopTest();

    ReturnEligibilityResult result = results.get(orderItem.Id);

    debugResult('CATEGORY_NOT_RETURNABLE', result);

    System.assertEquals(false, result.eligible);

    System.assertEquals('CATEGORY_NOT_RETURNABLE', result.code);

    System.assertEquals(
      null,
      result.returnDeadline,
      'Category bị cấm không cần tính deadline'
    );
  }

  @IsTest
  static void evaluate_ShouldReject_WhenDeliveryDateMissing() {
    PricebookEntry pricebookEntry = createProductAndPricebookEntry(
      'Test Phone',
      'PHONE-001',
      'Điện Thoại',
      12000000
    );

    OrderItem orderItem = createOrderItem(pricebookEntry, null);

    Test.startTest();

    Map<Id, ReturnEligibilityResult> results = ReturnEligibilityService.evaluate(
      new Set<Id>{ orderItem.Id },
      Date.newInstance(2026, 10, 21)
    );

    Test.stopTest();

    ReturnEligibilityResult result = results.get(orderItem.Id);

    debugResult('MISSING_DELIVERY_DATE', result);

    System.assertEquals(false, result.eligible);

    System.assertEquals('MISSING_DELIVERY_DATE', result.code);

    System.assertEquals(null, result.returnDeadline);
  }

  @IsTest
  static void evaluate_ShouldHandleMultipleOrderItems() {
    PricebookEntry laptopPricebookEntry = createProductAndPricebookEntry(
      'Bulk Laptop',
      'BULK-LAPTOP',
      'Laptop',
      20000000
    );

    PricebookEntry prepaidCardPricebookEntry = createProductAndPricebookEntry(
      'Bulk Prepaid Card',
      'BULK-CARD',
      'Thẻ Cào',
      500000
    );

    Date deliveryDate = Date.newInstance(2026, 10, 20);

    OrderItem laptopItem = createOrderItem(laptopPricebookEntry, deliveryDate);

    OrderItem prepaidCardItem = createOrderItem(
      prepaidCardPricebookEntry,
      deliveryDate
    );

    Set<Id> orderItemIds = new Set<Id>{ laptopItem.Id, prepaidCardItem.Id };

    System.debug(
      LoggingLevel.INFO,
      'TEST REQ-05 | BULK_INPUT' + ' | orderItemIds=' + orderItemIds
    );

    Test.startTest();

    Map<Id, ReturnEligibilityResult> results = ReturnEligibilityService.evaluate(
      orderItemIds,
      Date.newInstance(2026, 10, 21)
    );

    Test.stopTest();

    debugResult('BULK_LAPTOP_RESULT', results.get(laptopItem.Id));

    debugResult('BULK_PREPAID_CARD_RESULT', results.get(prepaidCardItem.Id));

    System.assertEquals(
      2,
      results.size(),
      'Phải xử lý được nhiều OrderItem trong một lần gọi'
    );

    System.assertEquals('ELIGIBLE', results.get(laptopItem.Id).code);

    System.assertEquals(
      'CATEGORY_NOT_RETURNABLE',
      results.get(prepaidCardItem.Id).code
    );
  }

  @IsTest
  static void evaluate_ShouldReturnEmpty_WhenInputEmpty() {
    Test.startTest();

    Map<Id, ReturnEligibilityResult> results = ReturnEligibilityService.evaluate(
      new Set<Id>()
    );

    Test.stopTest();

    System.debug(
      LoggingLevel.INFO,
      'TEST REQ-05 | EMPTY_INPUT' + ' | resultCount=' + results.size()
    );

    System.assertEquals(0, results.size());
  }
}
