public inherited sharing class StateTransitionService {
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
        new List<Return_Request__c>{ requestRecord },
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
