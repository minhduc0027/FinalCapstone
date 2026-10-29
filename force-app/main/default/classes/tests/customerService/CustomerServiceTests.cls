@IsTest
private class CustomerServiceTests {
  private static final String STORE_CODE = 'CS_TEST_STORE';

  //===================================================
  // Test setup
  //===================================================
  @TestSetup
  static void setupData() {
    Store__c storeRecord = new Store__c(
      Name = 'Customer Service Test Store',
      Store_Code__c = STORE_CODE
    );
    insert as system storeRecord;

    List<Account> customers = new List<Account>{
      new Account(Name = 'Customer Service Alpha', Phone = '0901000001'),
      new Account(Name = 'Customer Service Beta', Phone = '0902000002'),
      new Account(Name = 'Customer Service Gamma', Phone = '0903000003')
    };
    insert as system customers;

    List<Order> orders = new List<Order>();

    for (Account customer : customers) {
      orders.add(
        new Order(
          AccountId = customer.Id,
          Store__c = storeRecord.Id,
          EffectiveDate = Date.today(),
          Status = 'Draft'
        )
      );
    }

    insert as system orders;

    List<Return_Request__c> requests = new List<Return_Request__c>();

    for (Integer index = 0; index < customers.size(); index++) {
      requests.add(
        new Return_Request__c(
          Customer__c = customers[index].Id,
          Order__c = orders[index].Id,
          Store__c = storeRecord.Id,
          Status__c = SmartReturnConstants.STATUS_NEW,
          Source_Channel__c = SmartReturnConstants.SOURCE_APP,
          Estimated_Refund_Amount__c = (index + 1) * 100000
        )
      );
    }

    insert as system requests;
  }

  //===================================================
  // Helpers
  //===================================================
  private static CustomerServiceFilter newFilter(
    Integer pageSize,
    Integer offsetSize
  ) {
    CustomerServiceFilter filter = new CustomerServiceFilter();

    filter.pageSize = pageSize;

    filter.page = new DbPageRequest();
    filter.page.strategy = DbPageRequest.OFFSET;
    filter.page.offsetSize = offsetSize;

    return filter;
  }

  private static Account getCustomer(String name) {
    return [
      SELECT Id, Name, Phone
      FROM Account
      WHERE Name = :name
      LIMIT 1
    ];
  }

  private static Order getCustomerOrder(Id customerId) {
    return [
      SELECT Id, OrderNumber, AccountId
      FROM Order
      WHERE AccountId = :customerId
      LIMIT 1
    ];
  }

  //===================================================
  // Null filter and defaults
  //===================================================
  @IsTest
  static void getRequests_NullFilter_ShouldUseDefaults() {
    Test.startTest();

    CustomerServicePageResult result = CustomerService.getReturnRequestsForCustomerService(
      null
    );

    Test.stopTest();

    System.assertNotEquals(null, result, 'Service phải trả về page result.');

    System.assertNotEquals(null, result.records, 'Records không được null.');

    System.assertEquals(
      3,
      result.records.size(),
      'Null filter phải trả về toàn bộ test requests.'
    );

    System.assertEquals(
      false,
      result.hasNext,
      'Chỉ có 3 requests nên default page size 20 không có next page.'
    );

    System.assertNotEquals(
      null,
      result.bindCount,
      'Bind count phải được copy từ DbQueryResult.'
    );
  }

  //===================================================
  // Filter by customer phone
  //===================================================
  @IsTest
  static void getRequests_ShouldFilterByCustomerPhone() {
    CustomerServiceFilter filter = newFilter(20, 0);

    /*
     * Có khoảng trắng để cover normalizeSearchTerm().
     * Dùng partial phone để cover LIKE %term%.
     */
    filter.customerPhone = '  090200  ';

    Test.startTest();

    CustomerServicePageResult result = CustomerService.getReturnRequestsForCustomerService(
      filter
    );

    Test.stopTest();

    System.assertEquals(
      1,
      result.records.size(),
      'Phone filter phải chỉ tìm thấy Customer Service Beta.'
    );

    System.assertEquals(false, result.hasNext);
  }

  //===================================================
  // Filter by customer name
  //===================================================
  @IsTest
  static void getRequests_ShouldFilterByCustomerName() {
    CustomerServiceFilter filter = newFilter(20, 0);

    filter.customerName = '  Service Gamma  ';

    Test.startTest();

    CustomerServicePageResult result = CustomerService.getReturnRequestsForCustomerService(
      filter
    );

    Test.stopTest();

    System.assertEquals(
      1,
      result.records.size(),
      'Customer name filter phải hỗ trợ partial LIKE search.'
    );

    System.assertEquals(false, result.hasNext);
  }

  //===================================================
  // Filter by order number
  //===================================================
  @IsTest
  static void getRequests_ShouldFilterByOrderNumber() {
    Account customer = getCustomer('Customer Service Alpha');

    Order customerOrder = getCustomerOrder(customer.Id);

    CustomerServiceFilter filter = newFilter(20, 0);

    filter.orderNumber = '  ' + customerOrder.OrderNumber + '  ';

    Test.startTest();

    CustomerServicePageResult result = CustomerService.getReturnRequestsForCustomerService(
      filter
    );

    Test.stopTest();

    System.assertEquals(
      1,
      result.records.size(),
      'Order number filter phải tìm đúng request.'
    );

    System.assertEquals(false, result.hasNext);
  }

  //===================================================
  // Combined filters
  //===================================================
  @IsTest
  static void getRequests_ShouldCombineAllFilters() {
    Account customer = getCustomer('Customer Service Beta');

    Order customerOrder = getCustomerOrder(customer.Id);

    CustomerServiceFilter filter = newFilter(10, 0);

    filter.customerName = ' Service Beta ';

    filter.customerPhone = ' 0902000002 ';

    filter.orderNumber = ' ' + customerOrder.OrderNumber + ' ';

    Test.startTest();

    CustomerServicePageResult result = CustomerService.getReturnRequestsForCustomerService(
      filter
    );

    Test.stopTest();

    System.assertEquals(
      1,
      result.records.size(),
      'Ba filter hợp lệ phải match cùng một request.'
    );

    System.assertEquals(false, result.hasNext);

    System.assert(
      result.bindCount >= 3,
      'Query phải có bind values cho ba search filters.'
    );
  }

  //===================================================
  // No matching result
  //===================================================
  @IsTest
  static void getRequests_NoMatch_ShouldReturnEmptyPage() {
    CustomerServiceFilter filter = newFilter(20, 0);

    filter.customerPhone = 'PHONE_DOES_NOT_EXIST';

    filter.orderNumber = 'ORDER_DOES_NOT_EXIST';

    filter.customerName = 'CUSTOMER_DOES_NOT_EXIST';

    Test.startTest();

    CustomerServicePageResult result = CustomerService.getReturnRequestsForCustomerService(
      filter
    );

    Test.stopTest();

    System.assertNotEquals(null, result);
    System.assertNotEquals(null, result.records);

    System.assertEquals(
      0,
      result.records.size(),
      'Không có record phù hợp phải trả empty list.'
    );

    System.assertEquals(false, result.hasNext);
  }

  //===================================================
  // Blank filters
  //===================================================
  @IsTest
  static void getRequests_BlankSearchTerms_ShouldBeIgnored() {
    CustomerServiceFilter filter = newFilter(20, 0);

    filter.customerPhone = '   ';
    filter.orderNumber = '';
    filter.customerName = null;

    Test.startTest();

    CustomerServicePageResult result = CustomerService.getReturnRequestsForCustomerService(
      filter
    );

    Test.stopTest();

    System.assertEquals(
      3,
      result.records.size(),
      'Blank search terms không được tạo query filter.'
    );

    System.assertEquals(false, result.hasNext);
  }

  //===================================================
  // OFFSET pagination
  //===================================================
  @IsTest
  static void getRequests_ShouldSupportOffsetPagination() {
    CustomerServiceFilter firstPageFilter = newFilter(1, 0);

    CustomerServiceFilter secondPageFilter = newFilter(1, 1);

    CustomerServicePageResult firstPage;
    CustomerServicePageResult secondPage;

    Test.startTest();

    firstPage = CustomerService.getReturnRequestsForCustomerService(
      firstPageFilter
    );

    secondPage = CustomerService.getReturnRequestsForCustomerService(
      secondPageFilter
    );

    Test.stopTest();

    System.assertEquals(1, firstPage.records.size());

    System.assertEquals(
      true,
      firstPage.hasNext,
      'Page size 1 với 3 records phải có next page.'
    );

    System.assertEquals(1, secondPage.records.size());

    System.assertEquals(
      true,
      secondPage.hasNext,
      'Offset 1 vẫn còn record sau page hiện tại.'
    );
  }

  //===================================================
  // Last page
  //===================================================
  @IsTest
  static void getRequests_LastPage_ShouldNotHaveNext() {
    CustomerServiceFilter filter = newFilter(1, 2);

    Test.startTest();

    CustomerServicePageResult result = CustomerService.getReturnRequestsForCustomerService(
      filter
    );

    Test.stopTest();

    System.assertEquals(1, result.records.size());

    System.assertEquals(
      false,
      result.hasNext,
      'Record cuối không được báo còn next page.'
    );
  }

  //===================================================
  // Invalid page size
  //===================================================
  @IsTest
  static void getRequests_InvalidPageSize_ShouldUseDefault() {
    CustomerServiceFilter filter = newFilter(0, 0);

    Test.startTest();

    CustomerServicePageResult result = CustomerService.getReturnRequestsForCustomerService(
      filter
    );

    Test.stopTest();

    System.assertEquals(
      3,
      result.records.size(),
      'Page size <= 0 phải fallback về default size 20.'
    );

    System.assertEquals(false, result.hasNext);
  }

  //===================================================
  // Maximum page size
  //===================================================
  @IsTest
  static void getRequests_ExcessivePageSize_ShouldBeCapped() {
    CustomerServiceFilter filter = newFilter(999, 0);

    Test.startTest();

    CustomerServicePageResult result = CustomerService.getReturnRequestsForCustomerService(
      filter
    );

    Test.stopTest();

    System.assertEquals(
      3,
      result.records.size(),
      'Page size vượt maximum phải được cap ở 50.'
    );

    System.assertEquals(false, result.hasNext);
  }

  //===================================================
  // Null page
  //===================================================
  @IsTest
  static void getRequests_NullPage_ShouldUseOffsetZero() {
    CustomerServiceFilter filter = new CustomerServiceFilter();

    filter.pageSize = 1;
    filter.page = null;

    Test.startTest();

    CustomerServicePageResult result = CustomerService.getReturnRequestsForCustomerService(
      filter
    );

    Test.stopTest();

    System.assertEquals(1, result.records.size());

    System.assertEquals(true, result.hasNext);
  }

  //===================================================
  // Negative offset
  //===================================================
  @IsTest
  static void getRequests_NegativeOffset_ShouldUseZero() {
    CustomerServiceFilter filter = newFilter(1, -10);

    Test.startTest();

    CustomerServicePageResult result = CustomerService.getReturnRequestsForCustomerService(
      filter
    );

    Test.stopTest();

    System.assertEquals(
      1,
      result.records.size(),
      'Negative offset phải được normalize về 0.'
    );

    System.assertEquals(true, result.hasNext);
  }

  //===================================================
  // Client-provided pagination strategy
  //===================================================
  @IsTest
  static void getRequests_ShouldForceOffsetStrategy() {
    CustomerServiceFilter filter = new CustomerServiceFilter();

    filter.pageSize = 1;
    filter.page = new DbPageRequest();

    /*
     * Service phải bỏ qua strategy mà client gửi và tự ép OFFSET.
     */
    filter.page.strategy = 'KEYSET';
    filter.page.offsetSize = 1;
    filter.page.afterId = UserInfo.getUserId();
    filter.page.afterValue = 'client-controlled-value';

    Test.startTest();

    CustomerServicePageResult result = CustomerService.getReturnRequestsForCustomerService(
      filter
    );

    Test.stopTest();

    System.assertEquals(
      1,
      result.records.size(),
      'Service phải sử dụng OFFSET pagination bất kể client strategy.'
    );

    System.assertEquals(true, result.hasNext);
  }
}
