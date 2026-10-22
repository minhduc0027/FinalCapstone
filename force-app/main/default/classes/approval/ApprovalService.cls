public with sharing class ApprovalService {
  //===================================================
  // Manual Approval Route (Direct update from store manager or regional manager)
  // - Pending Approval -> Awaiting Goods
  // - Pending Approval -> Inspecting
  // - Pending Approval -> Rejected
  //===================================================
  public static void approveRequest(String caseId, String origin) {
    if (origin == 'App') {
      StateTransitionService.transition(
        caseId,
        'Awaiting Goods',
        'Approved by manager.'
      );
    } else {
      StateTransitionService.transition(
        caseId,
        'Inspecting',
        'Approved by manager.'
      );
    }
  }

  public static void rejectRequest(String caseId, String reason) {
    if (String.isBlank(reason)) {
      throw new StateTransitionException('Rejection reason cannot be blank.');
    }
    StateTransitionService.transition(caseId, 'Rejected', reason);
  }
}
