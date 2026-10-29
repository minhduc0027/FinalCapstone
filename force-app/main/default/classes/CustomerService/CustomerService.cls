public with sharing class CustomerService {
  private static final Integer DEFAULT_PAGE_SIZE = 20;
  private static final Integer MAX_PAGE_SIZE = 50;

  /*
   * SOSL trả tối đa 2,000 records tổng thể.
   * Giới hạn từng object giúp tránh candidate set quá lớn
   * trước khi query Return_Request__c.
   */
  private static final Integer SOSL_ACCOUNT_LIMIT = 1000;
  private static final Integer SOSL_ORDER_LIMIT = 1000;

  //===================================================
  // Main entry point
  //===================================================
  public static CustomerServicePageResult getReturnRequestsForCustomerService(
    CustomerServiceFilter filter
  ) {
    CustomerServiceFilter safeFilter = normalizeFilter(filter);

    CustomerServicePageResult emptyResult = buildEmptyPageResult();

    /*
     * Không cho search rỗng trả toàn bộ Return Request.
     */
    if (String.isBlank(safeFilter.searchTerm)) {
      return emptyResult;
    }

    SearchCandidates candidates = searchCandidates(safeFilter.searchTerm);

    if (candidates.customerIds.isEmpty() && candidates.orderIds.isEmpty()) {
      return emptyResult;
    }

    return queryReturnRequests(safeFilter, candidates);
  }

  //===================================================
  // SOSL candidate search
  //===================================================
  private static SearchCandidates searchCandidates(String searchTerm) {
    SearchCandidates candidates = new SearchCandidates();

    String soslSearchTerm = buildSoslSearchTerm(searchTerm);

    /*
     * Search trên:
     * - Account: Name, Phone và các searchable text fields.
     * - Order: OrderNumber và các searchable text fields.
     *
     * SOSL dùng để tìm candidate IDs.
     * SOQL phía sau mới quyết định Return Request nào được trả về.
     */
    String sosl =
      'FIND \'' +
      soslSearchTerm +
      '\' IN ALL FIELDS ' +
      'RETURNING ' +
      'Account(' +
      'Id, Name, Phone ' +
      'LIMIT ' +
      SOSL_ACCOUNT_LIMIT +
      '), ' +
      'Order(' +
      'Id, OrderNumber ' +
      'LIMIT ' +
      SOSL_ORDER_LIMIT +
      ') ' +
      'WITH USER_MODE';

    List<List<SObject>> searchResults;

    try {
      searchResults = Search.query(sosl);
    } catch (Exception e) {
      throw new CustomerServiceException(
        'Unable to search customer or order: ' + e.getMessage()
      );
    }

    /*
     * SOSL giữ thứ tự result list theo thứ tự object
     * trong RETURNING:
     *
     * 0 -> Account
     * 1 -> Order
     */
    if (!searchResults.isEmpty() && searchResults[0] != null) {
      for (SObject recordValue : searchResults[0]) {
        candidates.customerIds.add(recordValue.Id);
      }
    }

    if (searchResults.size() > 1 && searchResults[1] != null) {
      for (SObject recordValue : searchResults[1]) {
        candidates.orderIds.add(recordValue.Id);
      }
    }

    return candidates;
  }

  private static String buildSoslSearchTerm(String searchTerm) {
    String normalized = normalizeSearchTerm(searchTerm);

    if (String.isBlank(normalized)) {
      throw new CustomerServiceException('Search term không được để trống.');
    }

    /*
     * Loại bỏ các ký tự có ý nghĩa đặc biệt trong SOSL.
     *
     * Không cho client tự điều khiển:
     * - wildcard
     * - logical operators
     * - group expressions
     */
    String sanitized = normalized.replaceAll(
      '[\\?&|!\\{\\}\\[\\]\\(\\)\\^~\\*:\\"\\\\]',
      ' '
    );
    sanitized = sanitized.replaceAll('\\s+', ' ').trim();

    if (String.isBlank(sanitized)) {
      throw new CustomerServiceException(
        'Search term không chứa ký tự tìm kiếm hợp lệ.'
      );
    }

    /*
     * Escape dấu nháy trước khi ghép vào dynamic SOSL.
     * Wildcard do server append, không lấy từ client.
     */
    return String.escapeSingleQuotes(sanitized) + '*';
  }

  //===================================================
  // Return Request SOQL
  //===================================================
  private static CustomerServicePageResult queryReturnRequests(
    CustomerServiceFilter filter,
    SearchCandidates candidates
  ) {
    Integer pageSize = filter.pageSize;

    Integer offsetSize = filter.page == null ||
      filter.page.offsetSize == null
      ? 0
      : filter.page.offsetSize;

    Integer queryLimit = pageSize + 1;

    Map<String, Object> queryBinds = new Map<String, Object>{
      'queryLimit' => queryLimit,
      'offsetSize' => offsetSize
    };

    String whereClause;
    Boolean hasCustomers = !candidates.customerIds.isEmpty();
    Boolean hasOrders = !candidates.orderIds.isEmpty();

    if (hasCustomers && hasOrders) {
      queryBinds.put('customerIds', candidates.customerIds);
      queryBinds.put('orderIds', candidates.orderIds);

      whereClause =
        '(' +
        'Customer__c IN :customerIds ' +
        'OR Order__c IN :orderIds' +
        ')';
    } else if (hasCustomers) {
      queryBinds.put('customerIds', candidates.customerIds);
      whereClause = 'Customer__c IN :customerIds';
    } else {
      queryBinds.put('orderIds', candidates.orderIds);
      whereClause = 'Order__c IN :orderIds';
    }

    String soql =
      'SELECT ' +
      'Id, ' +
      'Name, ' +
      'Status__c, ' +
      'Estimated_Refund_Amount__c, ' +
      'Actual_Refund_Amount__c, ' +
      'Customer__c, ' +
      'Customer__r.Name, ' +
      'Customer__r.Phone, ' +
      'Order__c, ' +
      'Order__r.OrderNumber, ' +
      'Store__c, ' +
      'Store__r.Name, ' +
      'CreatedDate ' +
      'FROM Return_Request__c ' +
      'WHERE ' +
      whereClause +
      ' ORDER BY CreatedDate DESC, Id DESC ' +
      'LIMIT :queryLimit ' +
      'OFFSET :offsetSize';

    List<SObject> queryRecords;

    try {
      queryRecords = Database.queryWithBinds(
        soql,
        queryBinds,
        AccessLevel.USER_MODE
      );
    } catch (Exception e) {
      throw new CustomerServiceException(
        'Unable to query return requests: ' + e.getMessage()
      );
    }

    CustomerServicePageResult pageResult = new CustomerServicePageResult();

    pageResult.hasNext = queryRecords.size() > pageSize;

    if (pageResult.hasNext) {
      queryRecords.remove(queryRecords.size() - 1);
    }

    /*
     * bindCount giữ cùng semantics với DbQueryResult:
     * số lượng bind variables, không phải kích thước
     * của customerIds hoặc orderIds.
     */
    pageResult.bindCount = queryBinds.size();

    for (SObject recordValue : queryRecords) {
      Return_Request__c requestRecord = (Return_Request__c) recordValue;

      pageResult.records.add(
        CustomerServiceRequestRow.fromRecord(requestRecord)
      );
    }

    return pageResult;
  }

  //===================================================
  // Filter normalization
  //===================================================
  private static CustomerServiceFilter normalizeFilter(
    CustomerServiceFilter filter
  ) {
    CustomerServiceFilter safeFilter = filter == null
      ? new CustomerServiceFilter()
      : filter;

    safeFilter.searchTerm = normalizeSearchTerm(safeFilter.searchTerm);

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
     * Customer Service enforce OFFSET.
     */
    page.afterId = null;
    page.afterValue = null;

    return page;
  }

  private static String normalizeSearchTerm(String value) {
    if (String.isBlank(value)) {
      return null;
    }

    return value.trim().replaceAll('\\s+', ' ');
  }

  private static CustomerServicePageResult buildEmptyPageResult() {
    CustomerServicePageResult pageResult = new CustomerServicePageResult();

    pageResult.hasNext = false;
    pageResult.bindCount = 0;

    return pageResult;
  }

  //===================================================
  // Internal DTO
  //===================================================
  private class SearchCandidates {
    Set<Id> customerIds = new Set<Id>();

    Set<Id> orderIds = new Set<Id>();
  }

  public class CustomerServiceException extends Exception {
  }
}
