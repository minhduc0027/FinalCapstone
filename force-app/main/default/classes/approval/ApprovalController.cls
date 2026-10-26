public with sharing class ApprovalController {
  @AuraEnabled(cacheable=true)
  public static ApprovalPageResult getWorklist(ApprovalFilter filter) {
    return ApprovalService.getWorklist(filter);
  }

  @AuraEnabled
  public static void bulkApprove(List<Id> requestIds) {
    validateRequestIds(requestIds);
    ApprovalService.approveRequestBulk(requestIds);
  }

  @AuraEnabled
  public static void bulkReject(
    List<Id> requestIds,
    String reason,
    String staffNote
  ) {
    validateRequestIds(requestIds);
    ApprovalService.rejectRequestBulk(requestIds, reason, staffNote);
  }

  @AuraEnabled
  public static void reject(String requestId, String reason, String staffNote) {
    ApprovalService.rejectRequest(requestId, reason, staffNote);
  }

  private static void validateRequestIds(List<Id> requestIds) {
    if (requestIds == null || requestIds.isEmpty()) {
      throw new AuraHandledException(
        'At least one Return Request is required.'
      );
    }

    if (requestIds.size() > 200) {
      throw new AuraHandledException(
        'A maximum of 200 requests can be processed ' + 'at one time.'
      );
    }
  }
}
