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
        StateTransitionService.transition(returnRequest.Id, 'AWAITING_GOODS');
      } else {
        StateTransitionService.transition(returnRequest.Id, 'INSPECTING');
      }
    } else {
      StateTransitionService.transition(returnRequest.Id, 'PENDING_APPROVAL');
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
    // todo: risk flag check

    // auto approval feature flag check
    if (!SmartReturnConfigService.isFeatureEnabled('Auto_Approval')) {
      return false;
    }
    // refund amount check
    if (
      returnRequest.Actual_Refund_Amount__c >
      SmartReturnConfigService.getAutoApprovalLimit()
    ) {
      return false;
    }
    return true;
  }
}
