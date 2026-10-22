public with sharing class ApprovalService {
  //===================================================
  // Manual Approval Route (Direct update from store manager or regional manager)
  // - Pending Approval -> Awaiting Goods
  // - Pending Approval -> Inspecting
  // - Pending Approval -> Rejected
  //===================================================
  public static void approveRequest(String requestId, String sourceChannel) {
    // TODO: add validation approverId match currentUserId
    if (sourceChannel == 'APP') {
      StateTransitionService.transition(requestId, 'AWAITING_GOODS');
    } else {
      StateTransitionService.transition(requestId, 'INSPECTING');
    }
  }

  public static void rejectRequest(String requestId, String reason) {
    if (String.isBlank(reason)) {
      throw new StateTransitionService.StateTransitionException(
        'Rejection reason cannot be blank.'
      );
    }
    StateTransitionService.transition(requestId, 'REJECTED');
  }
}
