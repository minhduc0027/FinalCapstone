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
    String searchTerm,
    Integer pageSize,
    Integer offsetSize
  ) {
    CustomerServiceFilter filter = new CustomerServiceFilter();

    filter.searchTerm = searchTerm;
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

  private static List<Account> getAllCustomers() {
    return [
      SELECT Id, Name, Phone
      FROM Account
      WHERE Name LIKE 'Customer Service%'
      ORDER BY Name
    ];
  }

  private static List<Order> getAllOrders() {
    return [
      SELECT Id, OrderNumber, AccountId
      FROM Order
      WHERE Account.Name LIKE 'Customer Service%'
      ORDER BY Account.Name
    ];
  }

  private static void setSearchResults(List<Id> recordIds) {
    Test.setFixedSearchResults(recordIds);
  }

  //===================================================
  // Null filter
  //===================================================
  @IsTest
  static void getRequests_NullFilter_ShouldReturnEmptyPage() {
    Test.startTest();

    CustomerServicePageResult result = CustomerService.getReturnRequestsForCustomerService(
      null
    );

    Test.stopTest();

    System.assertNotEquals(null, result, 'Service phải trả về page result.');

    System.assertNotEquals(null, result.records, 'Records không được null.');

    System.assertEquals(
      0,
      result.records.size(),
      'Không có search term phải trả empty page.'
    );

    System.assertEquals(false, result.hasNext);

    System.assertEquals(0, result.bindCount);
  }

  //===================================================
  // Blank search term
  //===================================================
  @IsTest
  static void getRequests_BlankSearchTerm_ShouldReturnEmptyPage() {
    CustomerServiceFilter filter = newFilter('   ', 20, 0);

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
      'Blank search term không được trả toàn bộ requests.'
    );

    System.assertEquals(false, result.hasNext);

    System.assertEquals(0, result.bindCount);
  }

  //===================================================
  // Customer candidate
  //===================================================
  @IsTest
  static void getRequests_ShouldReturnRequestForCustomerCandidate() {
    Account customer = getCustomer('Customer Service Beta');

    CustomerServiceFilter filter = newFilter('090200', 20, 0);

    /*
     * Mock SOSL tìm thấy Account Beta.
     */
    setSearchResults(new List<Id>{ customer.Id });

    Test.startTest();

    CustomerServicePageResult result = CustomerService.getReturnRequestsForCustomerService(
      filter
    );

    Test.stopTest();

    System.assertEquals(
      1,
      result.records.size(),
      'Account candidate phải tìm được Return Request tương ứng.'
    );

    System.assertEquals(
      customer.Id,
      result.records[0].customerId,
      'Request trả về phải thuộc Customer Beta.'
    );

    System.assertEquals(false, result.hasNext);
  }

  //===================================================
  // Customer name search candidate
  //===================================================
  @IsTest
  static void getRequests_ShouldSupportCustomerNameSearch() {
    Account customer = getCustomer('Customer Service Gamma');

    CustomerServiceFilter filter = newFilter(
      '  Customer Service Gamma  ',
      20,
      0
    );

    setSearchResults(new List<Id>{ customer.Id });

    Test.startTest();

    CustomerServicePageResult result = CustomerService.getReturnRequestsForCustomerService(
      filter
    );

    Test.stopTest();

    System.assertEquals(
      1,
      result.records.size(),
      'Customer name search phải trả request của Account candidate.'
    );

    System.assertEquals(customer.Id, result.records[0].customerId);

    System.assertEquals(false, result.hasNext);
  }

  //===================================================
  // Order candidate
  //===================================================
  @IsTest
  static void getRequests_ShouldReturnRequestForOrderCandidate() {
    Account customer = getCustomer('Customer Service Alpha');

    Order customerOrder = getCustomerOrder(customer.Id);

    CustomerServiceFilter filter = newFilter(customerOrder.OrderNumber, 20, 0);

    /*
     * Mock SOSL tìm thấy Order thay vì Account.
     */
    setSearchResults(new List<Id>{ customerOrder.Id });

    Test.startTest();

    CustomerServicePageResult result = CustomerService.getReturnRequestsForCustomerService(
      filter
    );

    Test.stopTest();

    System.assertEquals(
      1,
      result.records.size(),
      'Order candidate phải tìm được Return Request tương ứng.'
    );

    System.assertEquals(
      customerOrder.Id,
      result.records[0].orderId,
      'Request phải thuộc đúng Order.'
    );

    System.assertEquals(false, result.hasNext);
  }

  //===================================================
  // Account + Order candidates
  //===================================================
  @IsTest
  static void getRequests_ShouldSupportCustomerOrOrderCandidates() {
    Account alpha = getCustomer('Customer Service Alpha');

    Account beta = getCustomer('Customer Service Beta');

    Order betaOrder = getCustomerOrder(beta.Id);

    CustomerServiceFilter filter = newFilter('Customer', 20, 0);

    /*
     * Search candidate chứa:
     * - Account Alpha
     * - Order của Beta
     *
     * Backend phải query:
     *
     * Customer__c IN :customerIds
     * OR
     * Order__c IN :orderIds
     */
    setSearchResults(new List<Id>{ alpha.Id, betaOrder.Id });

    Test.startTest();

    CustomerServicePageResult result = CustomerService.getReturnRequestsForCustomerService(
      filter
    );

    Test.stopTest();

    System.assertEquals(
      2,
      result.records.size(),
      'Account và Order candidates phải được kết hợp bằng OR.'
    );

    Set<Id> returnedCustomerIds = new Set<Id>();

    for (CustomerServiceRequestRow row : result.records) {
      returnedCustomerIds.add(row.customerId);
    }

    System.assertEquals(true, returnedCustomerIds.contains(alpha.Id));

    System.assertEquals(true, returnedCustomerIds.contains(beta.Id));

    System.assertEquals(false, result.hasNext);
  }

  //===================================================
  // No matching SOSL result
  //===================================================
  @IsTest
  static void getRequests_NoMatch_ShouldReturnEmptyPage() {
    CustomerServiceFilter filter = newFilter('DOES_NOT_EXIST', 20, 0);

    setSearchResults(new List<Id>());

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
      'Không có SOSL candidates phải trả empty list.'
    );

    System.assertEquals(false, result.hasNext);

    System.assertEquals(0, result.bindCount);
  }

  //===================================================
  // OFFSET pagination
  //===================================================
  @IsTest
  static void getRequests_ShouldSupportOffsetPagination() {
    List<Account> customers = getAllCustomers();

    List<Id> customerIds = new List<Id>();

    for (Account customer : customers) {
      customerIds.add(customer.Id);
    }

    CustomerServiceFilter firstPageFilter = newFilter('Customer Service', 1, 0);

    CustomerServiceFilter secondPageFilter = newFilter(
      'Customer Service',
      1,
      1
    );

    /*
     * Cả hai invocation đều sử dụng cùng candidate set.
     */
    setSearchResults(customerIds);

    CustomerServicePageResult firstPage;
    CustomerServicePageResult secondPage;

    Test.startTest();

    firstPage = CustomerService.getReturnRequestsForCustomerService(
      firstPageFilter
    );

    /*
     * Đặt lại fixed results trước invocation thứ hai
     * để intent của test rõ ràng.
     */
    setSearchResults(customerIds);

    secondPage = CustomerService.getReturnRequestsForCustomerService(
      secondPageFilter
    );

    Test.stopTest();

    System.assertEquals(1, firstPage.records.size());

    System.assertEquals(
      true,
      firstPage.hasNext,
      'Page size 1 với 3 matching requests phải có next page.'
    );

    System.assertEquals(1, secondPage.records.size());

    System.assertEquals(
      true,
      secondPage.hasNext,
      'Offset 1 vẫn còn record phía sau.'
    );

    System.assertNotEquals(
      firstPage.records[0].id,
      secondPage.records[0].id,
      'Hai page không được trả cùng một request.'
    );
  }

  //===================================================
  // Last page
  //===================================================
  @IsTest
  static void getRequests_LastPage_ShouldNotHaveNext() {
    List<Account> customers = getAllCustomers();

    List<Id> customerIds = new List<Id>();

    for (Account customer : customers) {
      customerIds.add(customer.Id);
    }

    CustomerServiceFilter filter = newFilter('Customer Service', 1, 2);

    setSearchResults(customerIds);

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
    List<Account> customers = getAllCustomers();

    List<Id> customerIds = new List<Id>();

    for (Account customer : customers) {
      customerIds.add(customer.Id);
    }

    CustomerServiceFilter filter = newFilter('Customer Service', 0, 0);

    setSearchResults(customerIds);

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
    List<Account> customers = getAllCustomers();

    List<Id> customerIds = new List<Id>();

    for (Account customer : customers) {
      customerIds.add(customer.Id);
    }

    CustomerServiceFilter filter = newFilter('Customer Service', 999, 0);

    setSearchResults(customerIds);

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
    List<Account> customers = getAllCustomers();

    List<Id> customerIds = new List<Id>();

    for (Account customer : customers) {
      customerIds.add(customer.Id);
    }

    CustomerServiceFilter filter = new CustomerServiceFilter();

    filter.searchTerm = 'Customer Service';

    filter.pageSize = 1;
    filter.page = null;

    setSearchResults(customerIds);

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
    List<Account> customers = getAllCustomers();

    List<Id> customerIds = new List<Id>();

    for (Account customer : customers) {
      customerIds.add(customer.Id);
    }

    CustomerServiceFilter filter = newFilter('Customer Service', 1, -10);

    setSearchResults(customerIds);

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
    List<Account> customers = getAllCustomers();

    List<Id> customerIds = new List<Id>();

    for (Account customer : customers) {
      customerIds.add(customer.Id);
    }

    CustomerServiceFilter filter = new CustomerServiceFilter();

    filter.searchTerm = 'Customer Service';

    filter.pageSize = 1;

    filter.page = new DbPageRequest();

    /*
     * Service phải bỏ qua strategy mà client gửi
     * và tự ép OFFSET.
     */
    filter.page.strategy = 'KEYSET';
    filter.page.offsetSize = 1;

    filter.page.afterId = UserInfo.getUserId();

    filter.page.afterValue = 'client-controlled-value';

    setSearchResults(customerIds);

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

  //===================================================
  // Special SOSL characters
  //===================================================
  @IsTest
  static void getRequests_SpecialCharacters_ShouldBeSanitized() {
    Account customer = getCustomer('Customer Service Alpha');

    CustomerServiceFilter filter = newFilter(
      '  Customer* Service? Alpha  ',
      20,
      0
    );

    setSearchResults(new List<Id>{ customer.Id });

    Test.startTest();

    CustomerServicePageResult result = CustomerService.getReturnRequestsForCustomerService(
      filter
    );

    Test.stopTest();

    System.assertEquals(
      1,
      result.records.size(),
      'SOSL special characters phải được sanitize mà không làm query fail.'
    );
  }

  //===================================================
  // Invalid search term
  //===================================================
  @IsTest
  static void getRequests_OnlySpecialCharacters_ShouldThrow() {
    CustomerServiceFilter filter = newFilter('***???', 20, 0);

    Boolean exceptionThrown = false;

    Test.startTest();

    try {
      CustomerService.getReturnRequestsForCustomerService(filter);
    } catch (CustomerService.CustomerServiceException e) {
      exceptionThrown = true;

      System.assert(
        e.getMessage().contains('không chứa ký tự tìm kiếm hợp lệ'),
        'Phải trả đúng validation message cho invalid search term.'
      );
    }

    Test.stopTest();

    System.assertEquals(
      true,
      exceptionThrown,
      'Search chỉ chứa SOSL special characters phải bị reject.'
    );
  }
}
