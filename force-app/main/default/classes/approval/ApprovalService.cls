public with sharing class ApprovalService {
  //===================================================
  // Manual Approval Route (Direct update from store manager or regional manager)
  // - Pending Approval -> Awaiting Goods
  // - Pending Approval -> Inspecting
  // - Pending Approval -> Rejected
  //===================================================
  public static void approveRequest(String requestId, String sourceChannel) {
    // TODO: add validation approverId match currentUserId
    if (sourceChannel == 'APP') {
      StateTransitionService.transition(
        requestId,
        SmartReturnConstants.STATUS_AWAITING_GOODS,
        null
      );
    } else {
      StateTransitionService.transition(
        requestId,
        SmartReturnConstants.STATUS_INSPECTING,
        null
      );
    }
  }

  public static void approveRequestBulk(
    List<Id> requestIds,
    String sourceChannel
  ) {
    // TODO: add validation approverId match currentUserId

    List<TransitionRequest> transitionRequests = new List<TransitionRequest>();
    for (Id requestId : requestIds) {
      transitionRequests.add(
        new TransitionRequest(
          requestId,
          sourceChannel == 'APP'
            ? SmartReturnConstants.STATUS_AWAITING_GOODS
            : SmartReturnConstants.STATUS_INSPECTING,
          null
        )
      );
    }
    StateTransitionService.transitionBulk(transitionRequests);
  }

  public static void rejectRequest(String requestId, String reason) {
    if (String.isBlank(reason)) {
      throw new StateTransitionService.StateTransitionException(
        'Rejection reason cannot be blank.'
      );
    }
    StateTransitionService.transition(
      requestId,
      SmartReturnConstants.STATUS_REJECTED,
      null
    );
  }
  public static void rejectRequestBulk(List<Id> requestIds) {
    List<TransitionRequest> transitionRequests = new List<TransitionRequest>();
    for (Id requestId : requestIds) {
      transitionRequests.add(
        new TransitionRequest(
          requestId,
          SmartReturnConstants.STATUS_REJECTED,
          null
        )
      );
    }
    StateTransitionService.transitionBulk(transitionRequests);
  }

  private static final Integer DEFAULT_PAGE_SIZE = 20;
  private static final Integer MAX_PAGE_SIZE = 50;
  private static final Set<String> ALLOWED_SORT_FIELDS = new Set<String>{
    'CreatedDate',
    'Estimated_Refund_Amount__c',
    'Actual_Refund_Amount__c',
    'Status__c',
    'Required_Approval_Level__c'
  };

  @AuraEnabled(cacheable=true)
  public static ApprovalPageResult getWorklist(ApprovalFilter filter) {
    ApprovalFilter safeFilter = filter == null ? new ApprovalFilter() : filter;
    DbQueryRequest queryRequest = buildWorklistQuery(safeFilter);
    DbQueryResult queryResult = DbQueryService.execute(
      queryRequest,
      MAX_PAGE_SIZE
    );

    ApprovalPageResult pageResult = new ApprovalPageResult();

    pageResult.hasNext = queryResult.hasNext;
    pageResult.bindCount = queryResult.bindCount;

    for (SObject recordValue : queryResult.records) {
      Return_Request__c requestRecord = (Return_Request__c) recordValue;

      pageResult.records.add(ApprovalRow.fromRecord(requestRecord));
    }

    return pageResult;
  }

  private static DbQueryRequest buildWorklistQuery(ApprovalFilter filter) {
    DbQueryRequest request = new DbQueryRequest();

    request.objectName = 'Return_Request__c';

    request.fields = new List<String>{
      'Id',
      'Name',
      'Status__c',
      'Required_Approval_Level__c',
      'ApproverId__c',
      'Estimated_Refund_Amount__c',
      'Actual_Refund_Amount__c',
      'Source_Channel__c',
      'Customer__c',
      'Customer__r.Name',
      'Store__c',
      'Store__r.Name',
      'CreatedDate'
    };

    request.filters = buildWorklistFilters(filter);

    request.orderBy = resolveSortField(filter.sortBy);

    request.orderDesc = filter.sortDescending == null
      ? true
      : filter.sortDescending;

    request.pageSize = filter.pageSize == null ||
      filter.pageSize <= 0
      ? DEFAULT_PAGE_SIZE
      : Math.min(filter.pageSize, MAX_PAGE_SIZE);

    request.page = filter.page == null
      ? buildDefaultPageRequest()
      : filter.page;
    request.page.strategy = DbPageRequest.OFFSET;

    return request;
  }

  private static List<FilterCondition> buildWorklistFilters(
    ApprovalFilter filter
  ) {
    List<FilterCondition> filters = new List<FilterCondition>();

    /*
     * Mặc định worklist chỉ lấy các request đang cần duyệt.
     * Nếu RE_CONFIRMING dùng chung approval worklist,
     * thay equality bằng IN theo khả năng của query compiler.
     */
    if (String.isBlank(filter.status)) {
      filters.add(
        new FilterCondition(
          'Status__c',
          '=',
          SmartReturnConstants.STATUS_PENDING_APPROVAL
        )
      );
    } else {
      validateApprovalStatus(filter.status);

      filters.add(new FilterCondition('Status__c', '=', filter.status));
    }

    if (String.isNotBlank(filter.approvalLevel)) {
      filters.add(
        new FilterCondition(
          'Required_Approval_Level__c',
          '=',
          filter.approvalLevel
        )
      );
    }

    if (filter.storeId != null) {
      filters.add(new FilterCondition('Store__c', '=', filter.storeId));
    }

    if (filter.assignedToMe == true) {
      filters.add(
        new FilterCondition('ApproverId__c', '=', UserInfo.getUserId())
      );
    }

    if (filter.fromDate != null) {
      filters.add(
        new FilterCondition(
          'CreatedDate',
          '>=',
          Datetime.newInstance(filter.fromDate, Time.newInstance(0, 0, 0, 0))
        )
      );
    }

    if (filter.toDate != null) {
      /*
       * Exclusive upper bound:
       * CreatedDate < 00:00 của ngày kế tiếp.
       */
      filters.add(
        new FilterCondition(
          'CreatedDate',
          '<',
          Datetime.newInstance(
            filter.toDate.addDays(1),
            Time.newInstance(0, 0, 0, 0)
          )
        )
      );
    }

    return filters;
  }

  private static String resolveSortField(String requestedSortField) {
    if (
      String.isBlank(requestedSortField) ||
      !ALLOWED_SORT_FIELDS.contains(requestedSortField)
    ) {
      return 'CreatedDate';
    }

    return requestedSortField;
  }

  private static void validateApprovalStatus(String status) {
    Set<String> supportedStatuses = new Set<String>{
      SmartReturnConstants.STATUS_PENDING_APPROVAL,
      SmartReturnConstants.STATUS_RE_CONFIRMING
    };

    if (!supportedStatuses.contains(status)) {
      throw new AuraHandledException('Unsupported approval worklist status.');
    }
  }

  private static DbPageRequest buildDefaultPageRequest() {
    DbPageRequest page = new DbPageRequest();

    page.strategy = DbPageRequest.OFFSET;

    /*
     * Nếu DbPageRequest có property offset/pageNumber,
     * đặt giá trị mặc định tương ứng tại đây.
     */

    return page;
  }
}
