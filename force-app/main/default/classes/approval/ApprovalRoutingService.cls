public with sharing class ApprovalRoutingService {
  //===================================================
  // Auto Approval Route
  // - New -> Pending Approval
  // - New -> Awaiting Goods
  // - New -> Inspecting
  //===================================================
  public static void evaluateInitialStatus(Return_Request__c returnRequest) {
    // reject criteria check Move to ReturnRequestValidator

    //if auto approval criteria check
    if (checkAutoApprovalCriterial(returnRequest)) {
      if (returnRequest.Source_Channel__c == smartReturnConstants.SOURCE_APP) {
        StateTransitionService.transition(
          returnRequest.Id,
          SmartReturnConstants.STATUS_AWAITING_GOODS,
          SmartReturnConstants.APPROVAL_AUTO
        );
      } else {
        StateTransitionService.transition(
          returnRequest.Id,
          SmartReturnConstants.STATUS_INSPECTING,
          SmartReturnConstants.APPROVAL_AUTO
        );
      }
    } else {
      Decimal storeApprovalLimit = SmartReturnConfigService.getStoreApprovalLimit();
      if (returnRequest.Estimated_Refund_Amount__c <= storeApprovalLimit) {
        StateTransitionService.transition(
          returnRequest.Id,
          SmartReturnConstants.STATUS_PENDING_APPROVAL,
          SmartReturnConstants.APPROVAL_CHT
        );
      } else {
        StateTransitionService.transition(
          returnRequest.Id,
          SmartReturnConstants.STATUS_PENDING_APPROVAL,
          SmartReturnConstants.APPROVAL_QLV
        );
      }
    }
  }

  public static String determineRequiredApprovalLevel(
    Id customerId,
    Decimal estimatedRefundAmount
  ) {
    Decimal refundAmount = estimatedRefundAmount == null
      ? 0
      : estimatedRefundAmount;

    Boolean isRisky = checkRiskCriteria(customerId);

    if (isRisky) {
      return SmartReturnConstants.APPROVAL_QLV;
    }

    Boolean autoApprovalEnabled = SmartReturnConfigService.isFeatureEnabled(
      'Auto_Approval'
    );

    if (
      autoApprovalEnabled &&
      refundAmount <= SmartReturnConfigService.getAutoApprovalLimit()
    ) {
      return SmartReturnConstants.APPROVAL_AUTO;
    }

    if (refundAmount <= SmartReturnConfigService.getStoreApprovalLimit()) {
      return SmartReturnConstants.APPROVAL_CHT;
    }

    return SmartReturnConstants.APPROVAL_QLV;
  }

  /**
   * auto approval feature flag check
   * risk flag check
   * refund amount check
   */
  private static Boolean checkAutoApprovalCriterial(
    Return_Request__c returnRequest
  ) {
    if (returnRequest == null || returnRequest.Customer__c == null) {
      return false;
    }

    if (checkRiskCriteria(returnRequest.Customer__c)) {
      return false;
    }

    if (!SmartReturnConfigService.isFeatureEnabled('Auto_Approval')) {
      return false;
    }

    if (
      returnRequest.Estimated_Refund_Amount__c >
      SmartReturnConfigService.getAutoApprovalLimit()
    ) {
      return false;
    }
    return true;
  }

  private static Boolean checkRiskCriteria(Id customerId) {
    if (customerId == null) {
      return false;
    }

    Integer dateWindow = SmartReturnConfigService.getRiskWindowDays();
    Integer riskRequestCount = SmartReturnConfigService.getRiskRequestCount();
    Decimal riskRefundAmount = SmartReturnConfigService.getRiskRefundAmount();

    AggregateResult result = [
      SELECT
        COUNT(Id) requestCount,
        SUM(Estimated_Refund_Amount__c) totalRefundAmount
      FROM Return_Request__c
      WHERE
        Customer__c = :customerId
        AND CreatedDate >= :System.now().addDays(-dateWindow)
        AND Status__c IN :SmartReturnConstants.ACTIVE_RETURN_STATUSES
    ];

    Integer requestCount = (Integer) result.get('requestCount');
    Decimal totalRefundAmount = (Decimal) result.get('totalRefundAmount');

    totalRefundAmount = totalRefundAmount == null ? 0 : totalRefundAmount;

    return requestCount >= riskRequestCount ||
      totalRefundAmount >= riskRefundAmount;
  }
}
