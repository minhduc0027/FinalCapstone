@IsTest
private class InspectionModuleTests {
  private static Return_Request__c createInspectionRequest() {
    Account customer = new Account(Name = 'Inspection Customer');
    insert customer;

    Store__c store = new Store__c(Store_Code__c = 'TEST-STORE');
    insert store;

    Product2 product = new Product2(
      Name = 'Laptop',
      ProductCode = 'LT001',
      Family = 'Laptop',
      IsActive = true
    );
    insert product;

    PricebookEntry pbe = new PricebookEntry(
      Pricebook2Id = Test.getStandardPricebookId(),
      Product2Id = product.Id,
      UnitPrice = 1000000,
      IsActive = true
    );
    insert pbe;

    Order orderRecord = new Order(
      AccountId = customer.Id,
      Store__c = store.Id,
      EffectiveDate = Date.today(),
      Delivery_Date__c = Date.today(),
      Status = 'Draft',
      Pricebook2Id = Test.getStandardPricebookId()
    );
    insert orderRecord;

    OrderItem orderItem = new OrderItem(
      OrderId = orderRecord.Id,
      PricebookEntryId = pbe.Id,
      Quantity = 2,
      UnitPrice = 1000000
    );
    insert orderItem;

    Return_Request__c requestRecord = new Return_Request__c(
      Customer__c = customer.Id,
      Order__c = orderRecord.Id,
      Store__c = store.Id,
      Status__c = SmartReturnConstants.STATUS_INSPECTING,
      Required_Approval_Level__c = SmartReturnConstants.APPROVAL_AUTO,
      Source_Channel__c = SmartReturnConstants.SOURCE_STORE
    );

    insert requestRecord;

    Return_Request_Line__c line = new Return_Request_Line__c(
      Return_Request__c = requestRecord.Id,
      Product__c = product.Id,
      Order_Item__c = orderItem.Id,
      Purchased_Quantity__c = 2,
      Requested_Quantity__c = 1,
      Unit_Price_Paid__c = 1000000,
      Return_Reason__c = 'TECHNICAL_DEFECT',
      Reported_Condition__c = 'SEALED'
    );

    insert line;

    return requestRecord;
  }

  @IsTest
  static void getReturnRequestLines_ShouldReturnData() {
    Return_Request__c requestRecord = createInspectionRequest();

    Test.startTest();

    List<Return_Request_Line__c> lines = InspectionController.getReturnRequestLines(
      requestRecord.Id
    );

    Test.stopTest();

    System.assertEquals(1, lines.size());

    System.assertEquals(requestRecord.Id, lines[0].Return_Request__c);
  }

  @IsTest
  static void getReturnRequestLines_ShouldReturnEmpty() {
    Test.startTest();

    List<Return_Request_Line__c> lines = InspectionController.getReturnRequestLines(
      null
    );

    Test.stopTest();

    System.assertEquals(0, lines.size());
  }

  @IsTest
  static void submitInspection_ShouldRejectAllLines() {
    Return_Request__c requestRecord = createInspectionRequest();

    Return_Request_Line__c line = [
      SELECT Id
      FROM Return_Request_Line__c
      WHERE Return_Request__c = :requestRecord.Id
      LIMIT 1
    ];

    line.Is_Eligible__c = false;
    line.Eligibility_Code__c = 'NOT_ELIGIBLE';
    line.Eligibility_Reason__c = 'DAMAGED';

    Test.startTest();

    InspectionController.submitInspection(
      new List<Return_Request_Line__c>{ line }
    );

    Test.stopTest();

    Return_Request__c updatedRequest = [
      SELECT Status__c
      FROM Return_Request__c
      WHERE Id = :requestRecord.Id
    ];

    System.assertEquals(
      SmartReturnConstants.STATUS_REJECTED,
      updatedRequest.Status__c
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
}
