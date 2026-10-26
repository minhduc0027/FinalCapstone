public with sharing class ApprovalController {
  private static final Integer MAX_BULK_SIZE = 200;

  @AuraEnabled(cacheable=true)
  public static ApprovalPageResult getWorklist(ApprovalFilter filter) {
    return ApprovalService.getWorklist(filter);
  }

  @AuraEnabled
  public static List<ApprovalActionResult> bulkApprove(List<Id> requestIds) {
    validateRequestIds(requestIds);

    try {
      return ApprovalService.approveRequestBulk(requestIds);
    } catch (ApprovalService.ApprovalException ex) {
      throw new AuraHandledException(ex.getMessage());
    }
  }

  @AuraEnabled
  public static List<ApprovalActionResult> bulkReject(
    List<Id> requestIds,
    String reason,
    String staffNote
  ) {
    validateRequestIds(requestIds);

    if (String.isBlank(reason)) {
      throw new AuraHandledException('Rejection reason is required.');
    }

    try {
      return ApprovalService.rejectRequestBulk(requestIds, reason, staffNote);
    } catch (ApprovalService.ApprovalException ex) {
      throw new AuraHandledException(ex.getMessage());
    }
  }

  private static void validateRequestIds(List<Id> requestIds) {
    if (requestIds == null || requestIds.isEmpty()) {
      throw new AuraHandledException(
        'At least one Return Request is required.'
      );
    }

    if (requestIds.size() > MAX_BULK_SIZE) {
      throw new AuraHandledException(
        'A maximum of 200 requests can be processed ' + 'at one time.'
      );
    }

    Set<Id> uniqueIds = new Set<Id>(requestIds);

    if (uniqueIds.contains(null) || uniqueIds.size() != requestIds.size()) {
      throw new AuraHandledException(
        'Return Request Ids must be non-null and unique.'
      );
    }
  }
}
