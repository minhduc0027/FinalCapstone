public with sharing class ApprovalRoutingService {
  /**
   * New -> Pending Approval
   * New -> Awaiting Goods
   * New -> Inspecting
   * New -> Rejected
   * Pending Approval -> Awaiting Goods
   * Pending Approval -> Inspecting
   * Pending Approval -> Rejected
   * Pending Approval -> Pending Approval (escalation)
   */

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
      if (returnRequest.Source_Channel__c == 'App') {
        StateTransitionService.transition(
          returnRequest.Id,
          SmartReturnConstants.STATUS_AWAITING_GOODS
        );
      } else {
        StateTransitionService.transition(
          returnRequest.Id,
          SmartReturnConstants.STATUS_INSPECTING
        );
      }
    } else {
      StateTransitionService.transition(
        returnRequest.Id,
        SmartReturnConstants.STATUS_PENDING_APPROVAL
      );
    }
  }
  /**
   * auto approval feature flag check
   * risk flag check
   * refund amount check
   */
  private static Boolean checkAutoApprovalCriterial(
    Return_Request__c returnRequest
  ) {
    //risk flag check
    Id customerId = returnRequest.Customer__c;
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
    ];
    Integer requestCount = (Integer) result.get('requestCount');
    Decimal totalRefundAmount = (Decimal) result.get('totalRefundAmount');
    Boolean isRisky =
      requestCount >= riskRequestCount ||
      totalRefundAmount >= riskRefundAmount;
    if (isRisky) {
      return false;
    }
    // auto approval feature flag check
    if (!SmartReturnConfigService.isFeatureEnabled('Auto_Approval')) {
      return false;
    }
    // refund amount check
    if (
      returnRequest.Estimated_Refund_Amount__c >
      SmartReturnConfigService.getAutoApprovalLimit()
    ) {
      return false;
    }
    return true;
  }
}
