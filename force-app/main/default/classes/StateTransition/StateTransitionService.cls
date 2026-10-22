public inherited sharing class StateTransitionService {
  public static final String STATUS_NEW = 'NEW';
  public static final String STATUS_PENDING_APPROVAL = 'PENDING_APPROVAL';
  public static final String STATUS_AWAITING_GOODS = 'AWAITING_GOODS';
  public static final String STATUS_INSPECTING = 'INSPECTING';
  public static final String STATUS_REFUND_PROCESSING = 'REFUND_PROCESSING';
  public static final String STATUS_COMPLETED = 'COMPLETED';
  public static final String STATUS_REFUND_FAILED = 'REFUND_FAILED';
  public static final String STATUS_REJECTED = 'REJECTED';
  public static final String STATUS_CANCELLED = 'CANCELLED';

  public static void transition(Id requestId, String targetStatus) {
    if (requestId == null) {
      throw new StateTransitionException('Return Request Id is required.');
    }
    Return_Request__c requestRecord = [
      SELECT Id, Status__c
      FROM Return_Request__c
      WHERE Id = :requestId
      LIMIT 1
      FOR UPDATE
    ];
    String oldStatus = requestRecord.Status__c;
    StateTransitionValidator.validate(oldStatus, targetStatus);
    requestRecord.Status__c = targetStatus;

    try {
      update requestRecord;
      LogService.info(
        requestRecord,
        'Status updated from ' + oldStatus + ' to ' + targetStatus,
        'StateTransitionService',
        'UPDATE'
      );
      LogService.insertLogs();
    } catch (Exception ex) {
      throw new StateTransitionException(ex.getMessage());
    }
  }
  public class StateTransitionException extends Exception {
  }
}
