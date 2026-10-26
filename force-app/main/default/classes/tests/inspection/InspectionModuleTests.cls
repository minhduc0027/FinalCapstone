@IsTest
private class InspectionModuleTests {
  private class TestData {
    public Account customer;
    public Store__c store;
    public Product2 product;
    public Order orderRecord;
    public OrderItem orderItem;
    public Return_Request__c requestRecord;
    public List<Return_Request_Line__c> lines;
  }

  //===================================================
  // Test data
  //===================================================
  private static TestData createInspectionData(Integer lineCount) {
    TestData data = new TestData();
    data.lines = new List<Return_Request_Line__c>();

    data.customer = new Account(Name = 'Inspection Customer');
    insert data.customer;

    data.store = new Store__c(
      Store_Code__c = 'TEST-' +
        String.valueOf(Math.abs(Crypto.getRandomInteger())).left(8)
    );
    insert data.store;

    data.product = new Product2(
      Name = 'Inspection Laptop',
      ProductCode = 'LT-' +
        String.valueOf(Math.abs(Crypto.getRandomInteger())).left(8),
      Family = 'Laptop',
      IsActive = true
    );
    insert data.product;

    PricebookEntry pricebookEntry = new PricebookEntry(
      Pricebook2Id = Test.getStandardPricebookId(),
      Product2Id = data.product.Id,
      UnitPrice = 1000000,
      IsActive = true
    );
    insert pricebookEntry;

    data.orderRecord = new Order(
      AccountId = data.customer.Id,
      Store__c = data.store.Id,
      EffectiveDate = Date.today(),
      Delivery_Date__c = Date.today(),
      Status = 'Draft',
      Pricebook2Id = Test.getStandardPricebookId()
    );
    insert data.orderRecord;

    data.orderItem = new OrderItem(
      OrderId = data.orderRecord.Id,
      PricebookEntryId = pricebookEntry.Id,
      Quantity = 5,
      UnitPrice = 1000000
    );
    insert data.orderItem;

    data.requestRecord = new Return_Request__c(
      Customer__c = data.customer.Id,
      Order__c = data.orderRecord.Id,
      Store__c = data.store.Id,
      Status__c = SmartReturnConstants.STATUS_INSPECTING,
      Required_Approval_Level__c = SmartReturnConstants.APPROVAL_AUTO,
      Source_Channel__c = SmartReturnConstants.SOURCE_STORE,
      Estimated_Refund_Amount__c = 1000000
    );
    insert data.requestRecord;

    for (Integer index = 0; index < lineCount; index++) {
      data.lines.add(
        new Return_Request_Line__c(
          Return_Request__c = data.requestRecord.Id,
          Product__c = data.product.Id,
          Order_Item__c = data.orderItem.Id,
          Purchased_Quantity__c = 5,
          Requested_Quantity__c = 1,
          Unit_Price_Paid__c = 1000000,
          Return_Reason__c = 'DEFECT',
          Reported_Condition__c = 'SEALED'
        )
      );
    }

    insert data.lines;

    return data;
  }

  private static Return_Request_Line__c buildRejectedInput(Id lineId) {
    return new Return_Request_Line__c(
      Id = lineId,
      Is_Eligible__c = false,
      Eligibility_Code__c = 'CATEGORY_NOT_RETURNABLE',
      Eligibility_Reason__c = 'DAMAGED'
    );
  }

  //===================================================
  // Controller tests
  //===================================================
  @IsTest
  static void getReturnRequestLines_ShouldReturnData() {
    TestData data = createInspectionData(1);

    Test.startTest();

    List<Return_Request_Line__c> lines = InspectionController.getReturnRequestLines(
      data.requestRecord.Id
    );

    Test.stopTest();

    System.assertEquals(
      1,
      lines.size(),
      'Controller phải trả về line của request.'
    );

    System.assertEquals(data.requestRecord.Id, lines[0].Return_Request__c);

    System.assertEquals(data.orderItem.Id, lines[0].Order_Item__c);

    System.assertEquals(1, lines[0].Requested_Quantity__c);
  }

  @IsTest
  static void getReturnRequestLines_ShouldThrowWhenIdIsNull() {
    Boolean exceptionThrown = false;

    Test.startTest();

    try {
      InspectionController.getReturnRequestLines(null);
    } catch (AuraHandledException ex) {
      exceptionThrown = true;
    }

    Test.stopTest();

    System.assertEquals(
      true,
      exceptionThrown,
      'Controller phải chặn Return Request Id null.'
    );
  }

  @IsTest
  static void submitInspection_ShouldThrowWhenInputEmpty() {
    Boolean exceptionThrown = false;

    Test.startTest();

    try {
      InspectionController.submitInspection(new List<Return_Request_Line__c>());
    } catch (AuraHandledException ex) {
      exceptionThrown = true;
    }

    Test.stopTest();

    System.assertEquals(true, exceptionThrown);
  }

  @IsTest
  static void submitInspection_ShouldThrowWhenInputNull() {
    Boolean exceptionThrown = false;

    Test.startTest();

    try {
      InspectionController.submitInspection(null);
    } catch (AuraHandledException ex) {
      exceptionThrown = true;
    }

    Test.stopTest();

    System.assertEquals(true, exceptionThrown);
  }

  //===================================================
  // Service success path without refund metadata
  //===================================================
  @IsTest
  static void submitInspection_ShouldRejectAllLines() {
    TestData data = createInspectionData(2);

    List<Return_Request_Line__c> inputLines = new List<Return_Request_Line__c>();

    for (Return_Request_Line__c storedLine : data.lines) {
      inputLines.add(buildRejectedInput(storedLine.Id));
    }

    Test.startTest();

    InspectionController.submitInspection(inputLines);

    Test.stopTest();

    Return_Request__c updatedRequest = [
      SELECT Status__c, Actual_Refund_Amount__c, Required_Approval_Level__c
      FROM Return_Request__c
      WHERE Id = :data.requestRecord.Id
    ];

    System.assertEquals(
      SmartReturnConstants.STATUS_REJECTED,
      updatedRequest.Status__c,
      'Tất cả line không eligible thì request phải REJECTED.'
    );

    System.assertEquals(
      0,
      updatedRequest.Actual_Refund_Amount__c,
      'Không có line eligible thì actual refund bằng 0.'
    );

    List<Return_Request_Line__c> updatedLines = [
      SELECT Is_Eligible__c, Eligibility_Code__c, Eligibility_Reason__c
      FROM Return_Request_Line__c
      WHERE Return_Request__c = :data.requestRecord.Id
    ];

    System.assertEquals(2, updatedLines.size());

    for (Return_Request_Line__c updatedLine : updatedLines) {
      System.assertEquals(false, updatedLine.Is_Eligible__c);

      System.assertEquals(
        'CATEGORY_NOT_RETURNABLE',
        updatedLine.Eligibility_Code__c
      );

      System.assertEquals('DAMAGED', updatedLine.Eligibility_Reason__c);
    }
  }

  //===================================================
  // Completeness validation
  //===================================================
  @IsTest
  static void processInspection_ShouldRejectPartialSubmission() {
    TestData data = createInspectionData(2);

    List<Return_Request_Line__c> partialInput = new List<Return_Request_Line__c>{
      buildRejectedInput(data.lines[0].Id)
    };

    Boolean exceptionThrown = false;

    Test.startTest();

    try {
      InspectionService.processInspection(partialInput);
    } catch (InspectionService.InspectionException ex) {
      exceptionThrown = true;
    }

    Test.stopTest();

    System.assertEquals(
      true,
      exceptionThrown,
      'Service phải chặn khi chưa submit đủ lines.'
    );

    Return_Request__c unchangedRequest = [
      SELECT Status__c
      FROM Return_Request__c
      WHERE Id = :data.requestRecord.Id
    ];

    System.assertEquals(
      SmartReturnConstants.STATUS_INSPECTING,
      unchangedRequest.Status__c,
      'Request phải giữ nguyên khi thiếu line.'
    );
  }

  @IsTest
  static void processInspection_ShouldRejectDuplicateLine() {
    TestData data = createInspectionData(1);

    Return_Request_Line__c input = buildRejectedInput(data.lines[0].Id);

    Boolean exceptionThrown = false;

    Test.startTest();

    try {
      InspectionService.processInspection(
        new List<Return_Request_Line__c>{ input, input }
      );
    } catch (InspectionService.InspectionException ex) {
      exceptionThrown = true;
    }

    Test.stopTest();

    System.assertEquals(
      true,
      exceptionThrown,
      'Service phải chặn line Id trùng.'
    );
  }

  @IsTest
  static void processInspection_ShouldRejectLineWithoutId() {
    Boolean exceptionThrown = false;

    Test.startTest();

    try {
      InspectionService.processInspection(
        new List<Return_Request_Line__c>{
          new Return_Request_Line__c(
            Is_Eligible__c = false,
            Eligibility_Code__c = 'CATEGORY_NOT_RETURNABLE',
            Eligibility_Reason__c = 'DAMAGED'
          )
        }
      );
    } catch (InspectionService.InspectionException ex) {
      exceptionThrown = true;
    }

    Test.stopTest();

    System.assertEquals(true, exceptionThrown);
  }

  //===================================================
  // Approval-level unit tests
  //===================================================
  @IsTest
  static void determineApprovalLevel_ShouldEscalateAutoToCht() {
    Decimal autoLimit = SmartReturnConfigService.getAutoApprovalLimit();

    Decimal storeLimit = SmartReturnConfigService.getStoreApprovalLimit();

    Decimal amount = Math.min(autoLimit + 1, storeLimit);

    String result = InspectionService.determineRequiredApprovalLevel(
      SmartReturnConstants.APPROVAL_AUTO,
      amount
    );

    System.assertEquals(SmartReturnConstants.APPROVAL_CHT, result);
  }

  @IsTest
  static void determineApprovalLevel_ShouldEscalateToQlv() {
    Decimal storeLimit = SmartReturnConfigService.getStoreApprovalLimit();

    String result = InspectionService.determineRequiredApprovalLevel(
      SmartReturnConstants.APPROVAL_CHT,
      storeLimit + 1
    );

    System.assertEquals(SmartReturnConstants.APPROVAL_QLV, result);
  }

  @IsTest
  static void determineApprovalLevel_ShouldNotDowngradeQlv() {
    String result = InspectionService.determineRequiredApprovalLevel(
      SmartReturnConstants.APPROVAL_QLV,
      0
    );

    System.assertEquals(SmartReturnConstants.APPROVAL_QLV, result);
  }

  @IsTest
  static void determineApprovalLevel_ShouldDefaultToAuto() {
    String result = InspectionService.determineRequiredApprovalLevel(null, 0);

    System.assertEquals(SmartReturnConstants.APPROVAL_AUTO, result);
  }

  //===================================================
  // Calculation validation
  //===================================================
  @IsTest
  static void calculateActualRefund_ShouldRejectNullLine() {
    Boolean exceptionThrown = false;

    try {
      InspectionService.calculateActualRefundAmount(null);
    } catch (InspectionService.InspectionException ex) {
      exceptionThrown = true;
    }

    System.assertEquals(true, exceptionThrown);
  }

  @IsTest
  static void calculateActualRefund_ShouldRejectMissingOrderItem() {
    Boolean exceptionThrown = false;

    try {
      InspectionService.calculateActualRefundAmount(
        new Return_Request_Line__c(
          Purchased_Quantity__c = 1,
          Requested_Quantity__c = 1
        )
      );
    } catch (InspectionService.InspectionException ex) {
      exceptionThrown = true;
    }

    System.assertEquals(true, exceptionThrown);
  }
}
