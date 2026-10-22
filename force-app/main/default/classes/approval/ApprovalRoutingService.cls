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
  public static void autoApprovalRoute(Case caseRecord) {
    // reject criteria check
    if (rejectCriteriaCheck(caseRecord)) {
      updateCaseStatus(caseRecord, 'Rejected');
      return;
    }

    //if auto approval is off, route to pending approval
    if (!SmartReturnConfigService.isFeatureEnabled('Auto_Approval')) {
      //update status to pending approval
      updateCaseStatus(caseRecord, 'Pending Approval');
      return;
    }

    //if auto approval is on, check criteria
    if (checkAutoApprovalCriterial(caseRecord)) {
      if (caseRecord.Origin == 'App') {
        updateCaseStatus(caseRecord, 'Awaiting Goods');
      } else {
        updateCaseStatus(caseRecord, 'Inspecting');
      }
    } else {
      updateCaseStatus(caseRecord, 'Pending Approval');
    }
  }
  /**
   * risk flag check
   * refund amount check
   */
  private static Boolean checkAutoApprovalCriterial(Case caseRecord) {
    // Placeholder for auto approval criteria logic
    // Return true if criteria met, otherwise false
    return false;
  }

  /**
   * Goods family type check,
   * Goods family type refund date check,
   */
  private static Boolean rejectCriteriaCheck(Case caseRecord) {
    // Placeholder for reject criteria logic
    return false;
  }

  //===================================================
  // Manual Approval Route (Direct update from store manager or regional manager)
  // - Pending Approval -> Awaiting Goods
  // - Pending Approval -> Inspecting
  // - Pending Approval -> Rejected
  // Very likely will not have a backend logic for this and will use lwc data service
  //===================================================
  public static void manualApprovalRoute() {
  }

  //===================================================
  // Escalation Route
  // - Pending Approval -> Pending Approval (escalation)
  // Planned to switch to nightly batch job
  //===================================================
  public static void escalationRoute() {
    // change approval pic from store manager to regional manager
  }

  //Helper methods
  public static void updateCaseStatus(Case caseRecord, String newStatus) {
    String oldStatus = caseRecord.Status;
    if (!StateTransitionValidator.isAllowed(oldStatus, newStatus)) {
      throw new StateTransitionValidator.StateTransitionException(
        'Invalid status transition from ' + oldStatus + ' to ' + newStatus
      );
    }
    caseRecord.Status = newStatus;
    Database.update(caseRecord, false);
    //Log trace
    LogService.info(
      caseRecord,
      'Status updated from ' + oldStatus + ' to ' + newStatus,
      'ApprovalRoutingService',
      'UPDATE'
    );
    LogService.insertLogs();
  }
}
