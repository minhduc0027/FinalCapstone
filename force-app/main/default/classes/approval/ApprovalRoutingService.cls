public with sharing class ApprovalRoutingService {
  public static void evaluateInitialStatus(Return_Request__c returnRequest) {
    if (returnRequest == null || returnRequest.Id == null) {
      throw new ApprovalRoutingException('Return Request is required.');
    }

    String approvalLevel = determineRequiredApprovalLevel(
      returnRequest.Customer__c,
      returnRequest.Estimated_Refund_Amount__c
    );

    if (approvalLevel == SmartReturnConstants.APPROVAL_AUTO) {
      String targetStatus = returnRequest.Source_Channel__c ==
        SmartReturnConstants.SOURCE_APP
        ? SmartReturnConstants.STATUS_AWAITING_GOODS
        : SmartReturnConstants.STATUS_INSPECTING;

      StateTransitionService.transition(
        returnRequest.Id,
        targetStatus,
        approvalLevel
      );

      notifyApprover(returnRequest.Id, approvalLevel);

      return;
    }

    StateTransitionService.transition(
      returnRequest.Id,
      SmartReturnConstants.STATUS_PENDING_APPROVAL,
      approvalLevel
    );

    notifyApprover(returnRequest.Id, approvalLevel);
  }

  public static String determineRequiredApprovalLevel(
    Id customerId,
    Decimal estimatedRefundAmount
  ) {
    Decimal amount = estimatedRefundAmount == null ? 0 : estimatedRefundAmount;

    if (isRiskCustomer(customerId)) {
      return SmartReturnConstants.APPROVAL_QLV;
    }

    if (
      SmartReturnConfigService.isFeatureEnabled('Auto_Approval') &&
      amount <= SmartReturnConfigService.getAutoApprovalLimit()
    ) {
      return SmartReturnConstants.APPROVAL_AUTO;
    }

    if (amount <= SmartReturnConfigService.getStoreApprovalLimit()) {
      return SmartReturnConstants.APPROVAL_CHT;
    }

    return SmartReturnConstants.APPROVAL_QLV;
  }

  @TestVisible
  private static Boolean isRiskCustomer(Id customerId) {
    if (customerId == null) {
      return false;
    }

    Integer windowDays = SmartReturnConfigService.getRiskWindowDays();

    AggregateResult result = [
      SELECT
        COUNT(Id) requestCount,
        SUM(Estimated_Refund_Amount__c) totalRefundAmount
      FROM Return_Request__c
      WHERE
        Customer__c = :customerId
        AND CreatedDate >= :System.now().addDays(-windowDays)
        AND Status__c IN :SmartReturnConstants.ACTIVE_RETURN_STATUSES
    ];

    Integer requestCount = (Integer) result.get('requestCount');
    Decimal totalAmount = (Decimal) result.get('totalRefundAmount');
    totalAmount = totalAmount == null ? 0 : totalAmount;

    return requestCount >= SmartReturnConfigService.getRiskRequestCount() ||
      totalAmount >= SmartReturnConfigService.getRiskRefundAmount();
  }

  //===================================================
  // Approval notification
  //===================================================
  @TestVisible
  private static void notifyApprover(Id returnRequestId, String approvalLevel) {
    Return_Request__c returnRequest = [
      SELECT
        Id,
        Name,
        Store__c,
        Store__r.Store_Manager__c,
        Store__r.Region_Manager__c
      FROM Return_Request__c
      WHERE Id = :returnRequestId
      LIMIT 1
    ];

    Set<Id> recipientIds = new Set<Id>();

    if (
      approvalLevel == SmartReturnConstants.APPROVAL_AUTO ||
      approvalLevel == SmartReturnConstants.APPROVAL_CHT
    ) {
      recipientIds.add(returnRequest.Store__r.Store_Manager__c);
    } else if (approvalLevel == SmartReturnConstants.APPROVAL_QLV) {
      recipientIds.add(returnRequest.Store__r.Region_Manager__c);
    }

    NotificationService.trySend(
      recipientIds,
      returnRequest.Id,
      'Yêu cầu hoàn tiền cần phê duyệt',
      'Yêu cầu ' +
        returnRequest.Name +
        ' đang chờ phê duyệt ở cấp ' +
        approvalLevel +
        '.'
    );
  }

  public class ApprovalRoutingException extends Exception {
  }
}
