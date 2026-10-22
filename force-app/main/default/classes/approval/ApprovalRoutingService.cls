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
  public static void evaluateInitialStatus(Case caseRecord) {
    // reject criteria check Move to ReturnRequestValidator

    //if auto approval criteria check
    if (checkAutoApprovalCriterial(caseRecord)) {
      if (caseRecord.Origin == 'App') {
        StateTransitionService.transition(
          caseRecord.Id,
          'Awaiting Goods',
          'Auto approved.'
        );
      } else {
        StateTransitionService.transition(
          caseRecord.Id,
          'Inspecting',
          'Auto approved.'
        );
      }
    } else {
      StateTransitionService.transition(
        caseRecord.Id,
        'Pending Approval',
        'Auto approval criteria not met.'
      );
    }
  }
  /**
   * auto approval feature flag check
   * risk flag check
   * refund amount check
   */
  private static Boolean checkAutoApprovalCriterial(Case caseRecord) {
    // todo: risk flag check

    // auto approval feature flag check
    if (!SmartReturnConfigService.isFeatureEnabled('Auto_Approval')) {
      return false;
    }
    // refund amount check
    if (
      caseRecord.Refund_Amount__c >
      SmartReturnConfigService.getAutoApprovalLimit()
    ) {
      return false;
    }
    return true;
  }
}
