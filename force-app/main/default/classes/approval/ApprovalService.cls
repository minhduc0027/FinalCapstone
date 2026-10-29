public with sharing class ApprovalService {
  private static final Integer DEFAULT_PAGE_SIZE = 20;
  private static final Integer MAX_PAGE_SIZE = 50;

  private static final Set<String> ALLOWED_SORT_FIELDS = new Set<String>{
    'CreatedDate',
    'Approval_Due_At__c',
    'Estimated_Refund_Amount__c',
    'Actual_Refund_Amount__c',
    'Status__c',
    'Required_Approval_Level__c'
  };

  //===================================================
  // Single approve
  //===================================================
  public static void approveRequest(Id requestId) {
    List<ApprovalActionResult> results = approveRequestBulk(
      new List<Id>{ requestId }
    );

    throwIfSingleFailed(results);
  }

  //===================================================
  // Bulk approve
  //===================================================
  public static List<ApprovalActionResult> approveRequestBulk(
    List<Id> requestIds
  ) {
    validateServiceRequestIds(requestIds);

    List<Return_Request__c> requests = queryApprovalRequests(requestIds);

    Map<Id, Return_Request__c> requestById = new Map<Id, Return_Request__c>(
      requests
    );

    List<ApprovalActionResult> results = new List<ApprovalActionResult>();

    List<StateTransitionService.ApprovalTransitionRequest> transitions = new List<StateTransitionService.ApprovalTransitionRequest>();

    for (Id requestId : requestIds) {
      Return_Request__c requestRecord = requestById.get(requestId);

      String validationError = validateApprovalAction(requestRecord);

      if (validationError != null) {
        results.add(ApprovalActionResult.failure(requestId, validationError));
        continue;
      }

      String targetStatus = determineApproveTarget(requestRecord);

      transitions.add(
        new StateTransitionService.ApprovalTransitionRequest(
          requestRecord.Id,
          targetStatus,
          requestRecord.Required_Approval_Level__c,
          null,
          null
        )
      );
    }

    results.addAll(
      convertTransitionResults(
        StateTransitionService.transitionApprovalBulk(transitions)
      )
    );

    return orderResults(requestIds, results);
  }

  //===================================================
  // Single reject
  //===================================================
  public static void rejectRequest(
    Id requestId,
    String reason,
    String staffNote
  ) {
    List<ApprovalActionResult> results = rejectRequestBulk(
      new List<Id>{ requestId },
      reason,
      staffNote
    );

    throwIfSingleFailed(results);
  }

  //===================================================
  // Bulk reject
  //===================================================
  public static List<ApprovalActionResult> rejectRequestBulk(
    List<Id> requestIds,
    String reason,
    String staffNote
  ) {
    validateServiceRequestIds(requestIds);

    if (String.isBlank(reason)) {
      throw new ApprovalException('Rejection reason is required.');
    }

    List<Return_Request__c> requests = queryApprovalRequests(requestIds);

    Map<Id, Return_Request__c> requestById = new Map<Id, Return_Request__c>(
      requests
    );

    List<ApprovalActionResult> results = new List<ApprovalActionResult>();

    List<StateTransitionService.ApprovalTransitionRequest> transitions = new List<StateTransitionService.ApprovalTransitionRequest>();

    for (Id requestId : requestIds) {
      Return_Request__c requestRecord = requestById.get(requestId);

      String validationError = validateApprovalAction(requestRecord);

      if (validationError != null) {
        results.add(ApprovalActionResult.failure(requestId, validationError));
        continue;
      }

      transitions.add(
        new StateTransitionService.ApprovalTransitionRequest(
          requestRecord.Id,
          SmartReturnConstants.STATUS_REJECTED,
          null,
          reason,
          staffNote
        )
      );
    }

    results.addAll(
      convertTransitionResults(
        StateTransitionService.transitionApprovalBulk(transitions)
      )
    );

    return orderResults(requestIds, results);
  }

  //===================================================
  // Query / authorization
  //===================================================
  private static List<Return_Request__c> queryApprovalRequests(
    List<Id> requestIds
  ) {
    return [
      SELECT
        Id,
        Status__c,
        Source_Channel__c,
        Required_Approval_Level__c,
        ApproverId__c,
        CreatedById
      FROM Return_Request__c
      WHERE Id IN :requestIds
      FOR UPDATE
    ];
  }

  private static String validateApprovalAction(
    Return_Request__c requestRecord
  ) {
    if (requestRecord == null) {
      return 'Return Request not found.';
    }

    if (
      requestRecord.Status__c != SmartReturnConstants.STATUS_PENDING_APPROVAL &&
      requestRecord.Status__c != SmartReturnConstants.STATUS_RE_CONFIRMING
    ) {
      return 'Request is no longer waiting for approval.';
    }

    if (requestRecord.ApproverId__c == null) {
      return 'Assigned approver is missing.';
    }

    if (requestRecord.ApproverId__c != UserInfo.getUserId()) {
      return 'Only the assigned approver can process this request.';
    }

    // if (requestRecord.CreatedById == UserInfo.getUserId()) {
    //   return 'Request creator cannot approve or reject ' + 'their own request.';
    // }

    return null;
  }

  private static String determineApproveTarget(
    Return_Request__c requestRecord
  ) {
    if (requestRecord.Status__c == SmartReturnConstants.STATUS_RE_CONFIRMING) {
      return SmartReturnConstants.STATUS_REFUND_PROCESSING;
    }

    return requestRecord.Source_Channel__c == SmartReturnConstants.SOURCE_APP
      ? SmartReturnConstants.STATUS_AWAITING_GOODS
      : SmartReturnConstants.STATUS_INSPECTING;
  }

  //===================================================
  // Result mapping
  //===================================================
  private static List<ApprovalActionResult> convertTransitionResults(
    List<TransitionResult> transitionResults
  ) {
    List<ApprovalActionResult> results = new List<ApprovalActionResult>();

    for (TransitionResult item : transitionResults) {
      results.add(
        new ApprovalActionResult(item.requestId, item.success, item.message)
      );
    }

    return results;
  }

  private static List<ApprovalActionResult> orderResults(
    List<Id> requestedIds,
    List<ApprovalActionResult> results
  ) {
    Map<Id, ApprovalActionResult> resultById = new Map<Id, ApprovalActionResult>();

    for (ApprovalActionResult item : results) {
      if (item.requestId != null) {
        resultById.put(item.requestId, item);
      }
    }

    List<ApprovalActionResult> ordered = new List<ApprovalActionResult>();

    for (Id requestId : requestedIds) {
      ApprovalActionResult item = resultById.get(requestId);

      ordered.add(
        item == null
          ? ApprovalActionResult.failure(requestId, 'No result returned.')
          : item
      );
    }

    return ordered;
  }

  private static void throwIfSingleFailed(List<ApprovalActionResult> results) {
    if (results == null || results.isEmpty() || results[0].success != true) {
      throw new ApprovalException(
        results == null || results.isEmpty()
          ? 'Approval action failed.'
          : results[0].message
      );
    }
  }

  private static void validateServiceRequestIds(List<Id> requestIds) {
    if (requestIds == null || requestIds.isEmpty()) {
      throw new ApprovalException('At least one Return Request is required.');
    }

    Set<Id> uniqueIds = new Set<Id>(requestIds);

    if (uniqueIds.contains(null) || uniqueIds.size() != requestIds.size()) {
      throw new ApprovalException(
        'Return Request Ids must be non-null and unique.'
      );
    }

    if (requestIds.size() > 200) {
      throw new ApprovalException(
        'A maximum of 200 requests can be processed at one time.'
      );
    }
  }

  //===================================================
  // Worklist
  //===================================================
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
      pageResult.records.add(
        ApprovalRow.fromRecord((Return_Request__c) recordValue)
      );
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
      'Store__r.Store_Code__c',
      'Store__r.Name',
      'Approval_Due_At__c',
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

    if (String.isBlank(request.page.strategy)) {
      request.page.strategy = DbPageRequest.OFFSET;
    }

    return request;
  }

  private static List<FilterCondition> buildWorklistFilters(
    ApprovalFilter filter
  ) {
    List<FilterCondition> filters = new List<FilterCondition>();

    if (String.isBlank(filter.status)) {
      filters.add(
        new FilterCondition(
          'Status__c',
          'IN',
          new List<String>{
            SmartReturnConstants.STATUS_PENDING_APPROVAL,
            SmartReturnConstants.STATUS_RE_CONFIRMING
          }
        )
      );
    } else {
      validateApprovalStatus(filter.status);

      filters.add(new FilterCondition('Status__c', '=', filter.status));
    }

    /*
     * Server-enforced. LWC không được bỏ filter này.
     */
    filters.add(
      new FilterCondition('ApproverId__c', '=', UserInfo.getUserId())
    );

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

    if (filter.customerId != null) {
      filters.add(new FilterCondition('Customer__c', '=', filter.customerId));
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
    return String.isBlank(requestedSortField) ||
      !ALLOWED_SORT_FIELDS.contains(requestedSortField)
      ? 'CreatedDate'
      : requestedSortField;
  }

  private static void validateApprovalStatus(String status) {
    if (
      status != SmartReturnConstants.STATUS_PENDING_APPROVAL &&
      status != SmartReturnConstants.STATUS_RE_CONFIRMING
    ) {
      throw new AuraHandledException('Unsupported approval worklist status.');
    }
  }

  private static DbPageRequest buildDefaultPageRequest() {
    DbPageRequest page = new DbPageRequest();

    page.strategy = DbPageRequest.OFFSET;

    return page;
  }

  public class ApprovalException extends Exception {
  }
}
