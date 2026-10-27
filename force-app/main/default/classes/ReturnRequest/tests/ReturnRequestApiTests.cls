@IsTest
private class ReturnRequestApiTests {
  @IsTest
  static void testCompileAndSmoke() {
    Store__c store = new Store__c(
      Name = 'Store Test',
      Store_Code__c = 'STORE-01',
      Region__c = 'Nam'
    );
    insert store;

    Account customer = new Account(
      Name = 'Customer Test',
      Phone = '0900111111'
    );
    insert customer;

    Order o = new Order(
      AccountId = customer.Id,
      Store__c = store.Id,
      EffectiveDate = Date.today(),
      Delivery_Date__c = Date.today(),
      Status = 'Draft',
      Pricebook2Id = Test.getStandardPricebookId()
    );
    insert o;

    o = [
      SELECT Id, OrderNumber
      FROM Order
      WHERE Id = :o.Id
      LIMIT 1
    ];

    Product2 p = new Product2(
      Name = 'Laptop',
      ProductCode = 'SKU-01',
      Family = 'Laptop',
      IsActive = true
    );
    insert p;

    PricebookEntry pbe = new PricebookEntry(
      Pricebook2Id = Test.getStandardPricebookId(),
      Product2Id = p.Id,
      UnitPrice = 100,
      IsActive = true
    );
    insert pbe;

    OrderItem oi = new OrderItem(
      OrderId = o.Id,
      PricebookEntryId = pbe.Id,
      Quantity = 5,
      UnitPrice = 100
    );
    insert oi;

    ReturnApiRequest req = new ReturnApiRequest();
    req.externalRequestId = 'REQ16-TEST';
    req.channel = 'POS';
    req.orderNumber = o.OrderNumber;
    req.customerPhone = customer.Phone;
    req.storeCode = store.Store_Code__c;

    ReturnApiRequest.ReturnApiLineRequest line = new ReturnApiRequest.ReturnApiLineRequest();

    line.sku = p.ProductCode;
    line.quantity = 1;
    line.reason = 'DEFECT';
    line.condition = 'SEALED';

    req.lines = new List<ReturnApiRequest.ReturnApiLineRequest>{ line };

    RestRequest request = new RestRequest();
    request.requestUri = '/services/apexrest/smartreturn/v1/return-requests';
    request.httpMethod = 'POST';
    request.requestBody = Blob.valueOf(JSON.serialize(req));

    RestContext.request = request;
    RestContext.response = new RestResponse();

    Test.startTest();

    ReturnRequestApi.createReturn();

    Test.stopTest();

    System.assertEquals(
      201,
      RestContext.response.statusCode,
      RestContext.response.responseBody == null
        ? 'No response body'
        : RestContext.response.responseBody.toString()
    );
  }
}
