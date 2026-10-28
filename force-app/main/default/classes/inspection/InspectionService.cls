public with sharing class InspectionService {
  private static final Integer DEFAULT_PAGE_SIZE = 20;
  private static final Integer MAX_PAGE_SIZE = 50;

  private static final Set<String> ALLOWED_WORKLIST_SORT_FIELDS = new Set<String>{
    'CreatedDate',
    'Estimated_Refund_Amount__c',
    'Source_Channel__c'
  };
  //===================================================
  // Inspection Worklist
  //===================================================
  public static InspectionPageResult getWorklist(InspectionFilter filter) {
    InspectionFilter safeFilter = filter == null
      ? new InspectionFilter()
      : filter;

    DbQueryRequest request = buildWorklistQuery(safeFilter);
    DbQueryResult result = DbQueryService.execute(request, MAX_PAGE_SIZE);
    InspectionPageResult pageResult = new InspectionPageResult();
    pageResult.hasNext = result.hasNext;
    pageResult.bindCount = result.bindCount;

    for (SObject recordValue : result.records) {
      pageResult.records.add(
        InspectionRow.fromRecord((Return_Request__c) recordValue)
      );
    }

    return pageResult;
  }

  private static DbQueryRequest buildWorklistQuery(InspectionFilter filter) {
    DbQueryRequest request = new DbQueryRequest();

    request.objectName = 'Return_Request__c';

    request.fields = new List<String>{
      'Id',
      'Name',
      'Status__c',
      'Source_Channel__c',
      'Customer__c',
      'Customer__r.Name',
      'Store__c',
      'Store__r.Name',
      'Estimated_Refund_Amount__c',
      'Inspection_Completed_At__c',
      'CreatedDate'
    };

    request.filters = buildWorklistFilters(filter);

    request.orderBy = resolveWorklistSortField(filter.sortBy);

    request.orderDesc = filter.sortDescending == null
      ? false
      : filter.sortDescending;

    request.pageSize = filter.pageSize == null ||
      filter.pageSize <= 0
      ? DEFAULT_PAGE_SIZE
      : Math.min(filter.pageSize, MAX_PAGE_SIZE);

    request.page = filter.page == null
      ? buildDefaultWorklistPage()
      : filter.page;

    /*
     * Inspection page hiện dùng OFFSET pagination.
     * Không cho client đổi strategy.
     */
    request.page.strategy = DbPageRequest.OFFSET;

    return request;
  }
  private static List<FilterCondition> buildWorklistFilters(
    InspectionFilter filter
  ) {
    List<FilterCondition> filters = new List<FilterCondition>();

    /*
     * Server-owned constraints.
     */
    filters.add(
      new FilterCondition(
        'Status__c',
        '=',
        SmartReturnConstants.STATUS_INSPECTING
      )
    );

    filters.add(new FilterCondition('Inspection_Completed_At__c', '=', null));

    if (filter.storeId != null) {
      filters.add(new FilterCondition('Store__c', '=', filter.storeId));
    }

    if (String.isNotBlank(filter.sourceChannel)) {
      filters.add(
        new FilterCondition('Source_Channel__c', '=', filter.sourceChannel)
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

  private static String resolveWorklistSortField(String requestedSortField) {
    if (
      String.isBlank(requestedSortField) ||
      !ALLOWED_WORKLIST_SORT_FIELDS.contains(requestedSortField)
    ) {
      return 'CreatedDate';
    }

    return requestedSortField;
  }

  private static DbPageRequest buildDefaultWorklistPage() {
    DbPageRequest page = new DbPageRequest();

    page.strategy = DbPageRequest.OFFSET;

    page.offsetSize = 0;

    return page;
  }

  //===================================================
  // Main entry point
  //===================================================
  public static void processInspection(
    List<Return_Request_Line__c> inputLines
  ) {
    if (inputLines == null || inputLines.isEmpty()) {
      throw new InspectionException('Inspection lines không được để trống.');
    }

    /*
     * Input từ LWC chỉ được tin cậy ở:
     * - Id
     * - Inspection_Result__c
     * - Eligibility_Code__c
     * - Eligibility_Reason__c
     */
    Map<Id, Return_Request_Line__c> inputById = validateAndBuildInputMap(
      inputLines
    );

    List<Return_Request_Line__c> submittedStoredLines = ReturnRequestSelector.getReturnRequestLinesByIds(
      inputById.keySet(),
      true
    );

    if (submittedStoredLines.size() != inputById.size()) {
      throw new InspectionException(
        'Không tìm thấy một hoặc nhiều Return Request Line.'
      );
    }

    Id requestId = validateSameRequest(submittedStoredLines);

    /*
     * Query toàn bộ line của Return Request.
     * Không cho phép hoàn tất inspection nếu LWC chỉ submit
     * một phần lines.
     */
    List<Return_Request_Line__c> storedLines = ReturnRequestSelector.getReturnRequestLines(
      requestId,
      true
    );

    if (storedLines.isEmpty()) {
      throw new InspectionException(
        'Return Request không có line để kiểm định.'
      );
    }

    validateAllLinesSubmitted(storedLines, inputById);

    Return_Request__c requestRecord = [
      SELECT
        Id,
        Status__c,
        Required_Approval_Level__c,
        Actual_Refund_Amount__c,
        Inspection_Completed_At__c
      FROM Return_Request__c
      WHERE Id = :requestId
      LIMIT 1
      FOR UPDATE
    ];

    if (requestRecord.Status__c != SmartReturnConstants.STATUS_INSPECTING) {
      throw new InspectionException(
        'Chỉ có thể kiểm định yêu cầu đang ở trạng thái INSPECTING.'
      );
    }

    Integer passedLineCount = 0;
    Decimal totalActualRefund = 0;

    List<Return_Request_Line__c> linesToUpdate = new List<Return_Request_Line__c>();

    for (Return_Request_Line__c storedLine : storedLines) {
      Return_Request_Line__c inputLine = inputById.get(storedLine.Id);

      applyInspectionInput(storedLine, inputLine);

      validateInspectionResult(storedLine);

      if (storedLine.Inspection_Result__c == 'PASSED') {
        passedLineCount++;

        totalActualRefund += calculateActualRefundAmount(storedLine);
      }

      linesToUpdate.add(
        new Return_Request_Line__c(
          Id = storedLine.Id,
          Inspection_Result__c = storedLine.Inspection_Result__c,
          Eligibility_Code__c = storedLine.Eligibility_Code__c,
          Eligibility_Reason__c = storedLine.Eligibility_Reason__c
        )
      );
    }

    update linesToUpdate;

    totalActualRefund = applyRefundRounding(totalActualRefund);

    String previousApprovalLevel = requestRecord.Required_Approval_Level__c;

    String requiredApprovalLevel = determineRequiredApprovalLevel(
      previousApprovalLevel,
      totalActualRefund
    );

    Boolean approvalLevelEscalated =
      previousApprovalLevel != requiredApprovalLevel;

    requestRecord.Actual_Refund_Amount__c = totalActualRefund;

    requestRecord.Required_Approval_Level__c = requiredApprovalLevel;

    requestRecord.Inspection_Completed_At__c = System.now();

    /*
     * TODO khi field và resolver sẵn sàng:
     *
     * if (approvalLevelEscalated) {
     *     requestRecord.ApproverId__c =
     *         ApproverResolver.resolve(
     *             requestRecord,
     *             requiredApprovalLevel
     *         );
     * }
     */

    update requestRecord;

    //===================================================
    // All lines rejected
    //===================================================
    if (passedLineCount == 0) {
      StateTransitionService.transition(
        requestId,
        SmartReturnConstants.STATUS_REJECTED,
        null,
        'All lines rejected'
      );

      logInspection(
        linesToUpdate,
        'Inspection completed. All lines were rejected.',
        'REJECT_INSPECTION'
      );

      return;
    }

    //===================================================
    // Actual amount requires higher approval authority
    //===================================================
    if (approvalLevelEscalated) {
      StateTransitionService.transition(
        requestId,
        'RE_CONFIRMING',
        requiredApprovalLevel
      );

      logInspection(
        linesToUpdate,
        'Inspection completed. Approval level changed from ' +
          previousApprovalLevel +
          ' to ' +
          requiredApprovalLevel +
          '.',
        'RE_CONFIRM_APPROVAL'
      );

      return;
    }

    //===================================================
    // Ready for PayHub
    //===================================================
    if (SmartReturnConfigService.isFeatureEnabled('Send_PayHub')) {
      // StateTransitionService.transition(
      //   requestId,
      //   SmartReturnConstants.STATUS_REFUND_PROCESSING,
      //   null
      // );
      RefundService.startRefund(requestId);

      logInspection(
        linesToUpdate,
        'Inspection completed. Request moved to refund processing.',
        'COMPLETE_INSPECTION'
      );

      return;
    }

    logInspection(
      linesToUpdate,
      'Inspection completed. Request remains INSPECTING because ' +
      'Send_PayHub is disabled.',
      'COMPLETE_INSPECTION'
    );
  }

  //===================================================
  // Actual refund calculation
  //===================================================
  private static Decimal applyRefundRounding(Decimal amount) {
    if (amount == null || amount <= 0) {
      return 0;
    }

    Decimal rounding = SmartReturnConfigService.getRefundRounding();

    if (rounding == null || rounding <= 0) {
      throw new InspectionException('Refund Rounding phải lớn hơn 0.');
    }

    Decimal units = (amount / rounding).setScale(0, RoundingMode.FLOOR);

    return units * rounding;
  }

  public static Decimal calculateActualRefundAmount(
    Return_Request_Line__c requestLine
  ) {
    if (requestLine == null) {
      throw new InspectionException('Return Request Line không được để trống.');
    }

    if (requestLine.Order_Item__c == null) {
      throw new InspectionException('Order Item không được để trống.');
    }

    if (
      requestLine.Order_Item__r == null ||
      requestLine.Order_Item__r.UnitPrice == null
    ) {
      throw new InspectionException(
        'Không tìm thấy Unit Price của Order Item.'
      );
    }

    Decimal refundableQuantity = getRefundableQuantity(requestLine);

    /*
     * refund matrix:
     * - Reported_Condition__c
     * - Return_Reason__c
     */
    Decimal refundRate = SmartReturnConfigService.getRefundRate(
      requestLine.Reported_Condition__c,
      requestLine.Return_Reason__c
    );

    if (refundRate == null || refundRate < 0) {
      throw new InspectionException(
        'Không tìm thấy refund rate hợp lệ cho condition/reason.'
      );
    }

    Decimal baseAmount =
      requestLine.Order_Item__r.UnitPrice * refundableQuantity;
    Decimal actualRefund = baseAmount * refundRate / 100;

    return actualRefund;
  }

  //===================================================
  // Approval-level re-evaluation
  //===================================================
  public static String determineRequiredApprovalLevel(
    String currentApprovalLevel,
    Decimal actualRefundAmount
  ) {
    Decimal amount = actualRefundAmount == null ? 0 : actualRefundAmount;

    Decimal autoApprovalLimit = SmartReturnConfigService.getAutoApprovalLimit();

    Decimal storeApprovalLimit = SmartReturnConfigService.getStoreApprovalLimit();

    /*
     * Vượt Store Approval Limit luôn cần QLV.
     */
    if (amount > storeApprovalLimit) {
      return SmartReturnConstants.APPROVAL_QLV;
    }

    /*
     * AUTO chỉ được tăng lên CHT nếu vượt Auto Approval Limit.
     */
    if (
      currentApprovalLevel == SmartReturnConstants.APPROVAL_AUTO &&
      amount > autoApprovalLimit
    ) {
      return SmartReturnConstants.APPROVAL_CHT;
    }

    /*
     * Defensive fallback khi dữ liệu cũ không có approval level.
     */
    if (String.isBlank(currentApprovalLevel)) {
      if (amount <= autoApprovalLimit) {
        return SmartReturnConstants.APPROVAL_AUTO;
      }

      return SmartReturnConstants.APPROVAL_CHT;
    }

    /*
     * Không downgrade authority:
     * - CHT vẫn là CHT nếu amount giảm.
     * - QLV vẫn là QLV.
     */
    return currentApprovalLevel;
  }

  //===================================================
  // Input validation
  //===================================================
  private static Map<Id, Return_Request_Line__c> validateAndBuildInputMap(
    List<Return_Request_Line__c> inputLines
  ) {
    Map<Id, Return_Request_Line__c> inputById = new Map<Id, Return_Request_Line__c>();

    for (Return_Request_Line__c inputLine : inputLines) {
      if (inputLine == null || inputLine.Id == null) {
        throw new InspectionException('Mỗi inspection line phải có Id.');
      }

      if (inputById.containsKey(inputLine.Id)) {
        throw new InspectionException(
          'Inspection line bị trùng: ' + inputLine.Id
        );
      }

      inputById.put(inputLine.Id, inputLine);
    }

    return inputById;
  }

  private static Id validateSameRequest(
    List<Return_Request_Line__c> storedLines
  ) {
    Id requestId;

    for (Return_Request_Line__c line : storedLines) {
      if (line.Return_Request__c == null) {
        throw new InspectionException(
          'Return Request của line không được để trống.'
        );
      }

      if (requestId == null) {
        requestId = line.Return_Request__c;

        continue;
      }

      if (requestId != line.Return_Request__c) {
        throw new InspectionException(
          'Tất cả inspection lines phải thuộc cùng một ' + 'Return Request.'
        );
      }
    }

    return requestId;
  }

  private static void validateAllLinesSubmitted(
    List<Return_Request_Line__c> storedLines,
    Map<Id, Return_Request_Line__c> inputById
  ) {
    if (storedLines.size() != inputById.size()) {
      throw new InspectionException(
        'Phải gửi kết quả kiểm định cho tất cả ' + 'Return Request Lines.'
      );
    }

    for (Return_Request_Line__c storedLine : storedLines) {
      if (!inputById.containsKey(storedLine.Id)) {
        throw new InspectionException(
          'Thiếu kết quả kiểm định cho line ' + storedLine.Id + '.'
        );
      }
    }
  }

  private static void applyInspectionInput(
    Return_Request_Line__c storedLine,
    Return_Request_Line__c inputLine
  ) {
    storedLine.Inspection_Result__c = inputLine.Inspection_Result__c;

    storedLine.Eligibility_Code__c = inputLine.Eligibility_Code__c;

    storedLine.Eligibility_Reason__c = inputLine.Eligibility_Reason__c;
  }

  private static void validateInspectionResult(Return_Request_Line__c line) {
    if (
      line.Inspection_Result__c != 'PASSED' &&
      line.Inspection_Result__c != 'FAILED'
    ) {
      throw new InspectionException(
        'Phải chọn chấp nhận hoặc từ chối cho line ' + line.Id + '.'
      );
    }

    if (String.isBlank(line.Eligibility_Code__c)) {
      throw new InspectionException(
        'Eligibility Code không được để trống cho line ' + line.Id + '.'
      );
    }

    if (String.isBlank(line.Eligibility_Reason__c)) {
      throw new InspectionException(
        'Eligibility Reason không được để trống cho line ' + line.Id + '.'
      );
    }
  }

  //===================================================
  // Quantity validation
  //===================================================
  private static Decimal getRefundableQuantity(Return_Request_Line__c line) {
    Decimal purchasedQuantity = line.Purchased_Quantity__c;

    Decimal requestedQuantity = line.Requested_Quantity__c;

    if (purchasedQuantity == null || purchasedQuantity <= 0) {
      throw new InspectionException(
        'Purchased Quantity phải lớn hơn 0 cho line ' + line.Id + '.'
      );
    }

    if (requestedQuantity == null || requestedQuantity <= 0) {
      throw new InspectionException(
        'Requested Quantity phải lớn hơn 0 cho line ' + line.Id + '.'
      );
    }

    if (requestedQuantity > purchasedQuantity) {
      throw new InspectionException(
        'Requested Quantity không được vượt Purchased Quantity ' +
          'cho line ' +
          line.Id +
          '.'
      );
    }

    return requestedQuantity;
  }

  //===================================================
  // Logging
  //===================================================
  private static void logInspection(
    List<Return_Request_Line__c> lines,
    String message,
    String operation
  ) {
    List<SObject> recordsToLog = new List<SObject>();

    recordsToLog.addAll(lines);

    LogService.info(recordsToLog, message, 'InspectionService', operation);

    LogService.insertLogs();
  }

  public class InspectionException extends Exception {
  }
}
