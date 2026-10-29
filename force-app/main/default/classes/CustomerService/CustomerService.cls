public with sharing class CustomerService {
  private static final Integer DEFAULT_PAGE_SIZE = 20;
  private static final Integer MAX_PAGE_SIZE = 50;

  public static CustomerServicePageResult getReturnRequestsForCustomerService(
    CustomerServiceFilter filter
  ) {
    CustomerServiceFilter safeFilter = normalizeFilter(filter);

    DbQueryRequest queryRequest = buildCustomerServiceQuery(safeFilter);

    DbQueryResult queryResult = DbQueryService.execute(
      queryRequest,
      MAX_PAGE_SIZE
    );

    CustomerServicePageResult pageResult = new CustomerServicePageResult();

    pageResult.hasNext = queryResult.hasNext;
    pageResult.bindCount = queryResult.bindCount;

    for (SObject recordValue : queryResult.records) {
      Return_Request__c requestRecord = (Return_Request__c) recordValue;

      pageResult.records.add(
        CustomerServiceRequestRow.fromRecord(requestRecord)
      );
    }

    return pageResult;
  }

  private static DbQueryRequest buildCustomerServiceQuery(
    CustomerServiceFilter filter
  ) {
    DbQueryRequest request = new DbQueryRequest();

    request.objectName = 'Return_Request__c';

    request.fields = new List<String>{
      'Id',
      'Name',
      'Status__c',
      'Estimated_Refund_Amount__c',
      'Actual_Refund_Amount__c',
      'Customer__c',
      'Customer__r.Name',
      'Customer__r.Phone',
      'Order__c',
      'Order__r.OrderNumber',
      'Store__c',
      'Store__r.Name',
      'CreatedDate'
    };

    request.filters = buildCustomerServiceFilters(filter);

    /*
     * Sort cố định để OFFSET pagination có kết quả ổn định hơn.
     *
     * Nếu DbQueryRequest chỉ hỗ trợ một orderBy field thì CreatedDate
     * là lựa chọn phù hợp cho màn hình Lookup.
     */
    request.orderBy = 'CreatedDate';
    request.orderDesc = true;

    request.pageSize = filter.pageSize;

    /*
     * Customer Service Lookup chỉ sử dụng OFFSET.
     * Không nhận strategy từ client để tránh UI đổi sang KEYSET
     * hoặc PAGE_CURSOR ngoài contract hiện tại.
     */
    request.page = buildOffsetPageRequest(filter.page);

    return request;
  }

  private static List<FilterCondition> buildCustomerServiceFilters(
    CustomerServiceFilter filter
  ) {
    List<FilterCondition> filters = new List<FilterCondition>();

    String customerPhone = normalizeSearchTerm(filter.customerPhone);

    String orderNumber = normalizeSearchTerm(filter.orderNumber);

    String customerName = normalizeSearchTerm(filter.customerName);

    if (String.isNotBlank(customerPhone)) {
      filters.add(
        new FilterCondition(
          'Customer__r.Phone',
          'LIKE',
          '%' + customerPhone + '%'
        )
      );
    }

    if (String.isNotBlank(orderNumber)) {
      filters.add(
        new FilterCondition(
          'Order__r.OrderNumber',
          'LIKE',
          '%' + orderNumber + '%'
        )
      );
    }

    if (String.isNotBlank(customerName)) {
      filters.add(
        new FilterCondition(
          'Customer__r.Name',
          'LIKE',
          '%' + customerName + '%'
        )
      );
    }

    return filters;
  }

  private static CustomerServiceFilter normalizeFilter(
    CustomerServiceFilter filter
  ) {
    CustomerServiceFilter safeFilter = filter == null
      ? new CustomerServiceFilter()
      : filter;

    safeFilter.customerPhone = normalizeSearchTerm(safeFilter.customerPhone);

    safeFilter.orderNumber = normalizeSearchTerm(safeFilter.orderNumber);

    safeFilter.customerName = normalizeSearchTerm(safeFilter.customerName);

    if (safeFilter.pageSize == null || safeFilter.pageSize <= 0) {
      safeFilter.pageSize = DEFAULT_PAGE_SIZE;
    } else {
      safeFilter.pageSize = Math.min(safeFilter.pageSize, MAX_PAGE_SIZE);
    }

    safeFilter.page = buildOffsetPageRequest(safeFilter.page);

    return safeFilter;
  }

  private static DbPageRequest buildOffsetPageRequest(
    DbPageRequest requestedPage
  ) {
    DbPageRequest page = new DbPageRequest();

    page.strategy = DbPageRequest.OFFSET;

    page.offsetSize = requestedPage == null ||
      requestedPage.offsetSize == null ||
      requestedPage.offsetSize < 0
      ? 0
      : requestedPage.offsetSize;

    /*
     * Không copy afterId và afterValue vì Customer Service Lookup
     * hiện chỉ hỗ trợ OFFSET pagination.
     */
    page.afterId = null;
    page.afterValue = null;

    return page;
  }

  private static String normalizeSearchTerm(String value) {
    if (String.isBlank(value)) {
      return null;
    }

    return value.trim();
  }
}
