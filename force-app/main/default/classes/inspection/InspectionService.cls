public with sharing class InspectionService {
  private static final String STATUS_RE_CONFIRMING = 'RE_CONFIRMING';

  /**
   * Main entry point.
   *
   * Input từ LWC chỉ nên chứa:
   * - Id
   * - Is_Eligible__c
   * - Eligibility_Code__c
   * - Eligibility_Reason__c
   *
   * Các field về giá, số lượng và parent phải được query lại
   * từ Salesforce, không tin dữ liệu gửi từ client.
   */
  public static void processInspection(
    List<Return_Request_Line__c> inputLines
  ) {
    if (inputLines == null || inputLines.isEmpty()) {
      throw new InspectionException('Inspection lines không được để trống.');
    }

    Map<Id, Return_Request_Line__c> inputById = validateAndBuildInputMap(
      inputLines
    );
    List<Return_Request_Line__c> storedLines = [
      SELECT
        Id,
        Return_Request__c,
        Is_Eligible__c,
        Eligibility_Code__c,
        Eligibility_Reason__c,
        Purchased_Quantity__c,
        Requested_Quantity__c,
        Order_Item__c,
        Order_Item__r.UnitPrice
      FROM Return_Request_Line__c
      WHERE Id IN :inputById.keySet()
      FOR UPDATE
    ];

    if (storedLines.size() != inputById.size()) {
      throw new InspectionException(
        'Không tìm thấy một hoặc nhiều Return Request Line.'
      );
    }

    Id requestId = validateSameRequest(storedLines);
    Return_Request__c requestRecord = [
      SELECT
        Id,
        Status__c,
        Required_Approval_Level__c,
        Actual_Refund_Amount__c,
        ApproverId__c
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

    Integer eligibleLineCount = 0;
    Decimal totalActualRefund = 0;

    for (Return_Request_Line__c storedLine : storedLines) {
      Return_Request_Line__c inputLine = inputById.get(storedLine.Id);

      applyInspectionInput(storedLine, inputLine);
      validateInspectionResult(storedLine);

      if (storedLine.Is_Eligible__c == true) {
        eligibleLineCount++;
        totalActualRefund += calculateActualRefundAmount(storedLine);
      }
    }

    /*
     * Update line trước. Nếu update parent hoặc transition lỗi,
     * toàn transaction vẫn rollback.
     */
    update storedLines;

    String previousApprovalLevel = requestRecord.Required_Approval_Level__c;
    String requiredApprovalLevel = determineRequiredApprovalLevel(
      previousApprovalLevel,
      totalActualRefund
    );

    Boolean approvalLevelEscalated =
      requiredApprovalLevel != previousApprovalLevel;
    requestRecord.Actual_Refund_Amount__c = totalActualRefund;
    requestRecord.Required_Approval_Level__c = requiredApprovalLevel;

    /*
     * TODO:
     * Nếu level đổi AUTO -> CHT hoặc CHT -> QLV,
     * resolve và gán ApproverId__c tại đây.
     *
     * requestRecord.ApproverId__c =
     *     ApproverResolver.resolve(
     *         requestRecord,
     *         requiredApprovalLevel
     *     );
     */
    update requestRecord;

    if (eligibleLineCount == 0) {
      StateTransitionService.transition(
        requestId,
        SmartReturnConstants.STATUS_REJECTED
      );

      logInspection(
        storedLines,
        'Inspection completed. All lines were rejected.',
        'REJECT_INSPECTION'
      );
      return;
    }

    if (approvalLevelEscalated) {
      // Cân nhắc thêm STATUS_RE_CONFIRMING = 'RE_CONFIRMING';
      StateTransitionService.transition(
        requestId,
        SmartReturnConstants.STATUS_PENDING_APPROVAL
      );
      logInspection(
        storedLines,
        'Inspection completed. Approval level changed from ' +
          previousApprovalLevel +
          ' to ' +
          requiredApprovalLevel +
          '.',
        'RE_CONFIRM_APPROVAL'
      );
      return;
    }

    if (SmartReturnConfigService.isFeatureEnabled('Send_PayHub')) {
      StateTransitionService.transition(
        requestId,
        SmartReturnConstants.STATUS_REFUND_PROCESSING
      );
      logInspection(
        storedLines,
        'Inspection completed. Request moved to refund processing.',
        'COMPLETE_INSPECTION'
      );
      return;
    }

    /*
     * Send_PayHub đang tắt:
     * - Status giữ nguyên INSPECTING
     * - Actual refund đã được cập nhật
     * - Không gọi StateTransitionService vì status không đổi
     */
    logInspection(
      storedLines,
      'Inspection completed. Request remains INSPECTING because ' +
      'Send_PayHub is disabled.',
      'COMPLETE_INSPECTION'
    );
  }

  /**
   * Formula:
   *
   * UnitPrice
   * x refundable quantity
   * x refund rate
   */
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

    Decimal refundRate = SmartReturnConfigService.getRefundRate(
      requestLine.Reported_Condition__c,
      requestLine.Eligibility_Reason__c // Could be Eligibility_Code__c
    );

    if (refundRate == null || refundRate < 0) {
      throw new InspectionException(
        'Không tìm thấy refund rate hợp lệ cho condition/reason.'
      );
    }

    Decimal baseAmount =
      requestLine.Order_Item__r.UnitPrice * refundableQuantity;
    Decimal actualRefund = baseAmount * refundRate / 100;
    return actualRefund.setScale(0);
  }

  /**
   * Chỉ escalate approval level, không downgrade:
   *
   * AUTO + actual > auto limit        -> CHT
   * AUTO/CHT + actual > store limit   -> QLV
   * QLV                               -> QLV
   */
  public static String determineRequiredApprovalLevel(
    String currentApprovalLevel,
    Decimal actualRefundAmount
  ) {
    Decimal amount = actualRefundAmount == null ? 0 : actualRefundAmount;

    Decimal autoApprovalLimit = SmartReturnConfigService.getAutoApprovalLimit();

    Decimal storeApprovalLimit = SmartReturnConfigService.getStoreApprovalLimit();

    if (amount > storeApprovalLimit) {
      return SmartReturnConstants.APPROVAL_QLV;
    }

    if (
      currentApprovalLevel == SmartReturnConstants.APPROVAL_AUTO &&
      amount > autoApprovalLimit
    ) {
      return SmartReturnConstants.APPROVAL_CHT;
    }

    if (String.isBlank(currentApprovalLevel)) {
      /*
       * Defensive fallback.
       * Request đi vào INSPECTING thông thường phải có level.
       */
      if (amount <= autoApprovalLimit) {
        return SmartReturnConstants.APPROVAL_AUTO;
      }
      return SmartReturnConstants.APPROVAL_CHT;
    }
    return currentApprovalLevel;
  }

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

  private static void applyInspectionInput(
    Return_Request_Line__c storedLine,
    Return_Request_Line__c inputLine
  ) {
    storedLine.Is_Eligible__c = inputLine.Is_Eligible__c;
    storedLine.Eligibility_Code__c = inputLine.Eligibility_Code__c;
    storedLine.Eligibility_Reason__c = inputLine.Eligibility_Reason__c;
  }

  private static void validateInspectionResult(Return_Request_Line__c line) {
    if (line.Is_Eligible__c == null) {
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

  /**
   * Quantity thực tế được hoàn:
   *
   * min(Requested Quantity, Purchased Quantity)
   */
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
