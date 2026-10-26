public inherited sharing class StateTransitionService {
  public static void validateBeforeUpdate(
    List<Return_Request__c> newRecords,
    Map<Id, Return_Request__c> oldRecordsById
  ) {
    if (newRecords == null || newRecords.isEmpty() || oldRecordsById == null) {
      return;
    }

    for (Return_Request__c newRecord : newRecords) {
      Return_Request__c oldRecord = oldRecordsById.get(newRecord.Id);
      if (oldRecord == null || oldRecord.Status__c == newRecord.Status__c) {
        continue;
      }

      try {
        StateTransitionValidator.validate(
          oldRecord.Status__c,
          newRecord.Status__c
        );
      } catch (StateTransitionValidator.StateTransitionException ex) {
        newRecord.Status__c.addError(ex.getMessage());
      }
    }
  }

  public static void transition(
    Id requestId,
    String targetStatus,
    String requiredApprovalLevel
  ) {
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
    if (String.isNotBlank(requiredApprovalLevel)) {
      requestRecord.Required_Approval_Level__c = requiredApprovalLevel;
    }
    if (targetStatus == SmartReturnConstants.STATUS_PENDING_APPROVAL) {
      requestRecord.Approval_Due_At__c = System.now()
        .addHours(SmartReturnConfigService.getApprovalTimeoutHours());
    }

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

  public static void transition(
    Id requestId,
    String targetStatus,
    String reason,
    String staffInternalNote
  ) {
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

    if (String.isNotBlank(reason)) {
      requestRecord.Rejection_Reason__c = reason;
    }
    if (String.isNotBlank(staffInternalNote)) {
      requestRecord.Internal_Notes__c = staffInternalNote;
    }

    if (targetStatus == SmartReturnConstants.STATUS_PENDING_APPROVAL) {
      requestRecord.Approval_Due_At__c = System.now()
        .addHours(SmartReturnConfigService.getApprovalTimeoutHours());
    }

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

  public static List<TransitionResult> transitionBulk(
    List<TransitionRequest> requests
  ) {
    return transitionBulk(requests, false);
  }

  public static List<TransitionResult> transitionBulk(
    List<TransitionRequest> requests,
    Boolean allOrNone
  ) {
    List<TransitionResult> results = new List<TransitionResult>();

    if (requests == null || requests.isEmpty()) {
      return results;
    }

    Set<Id> requestIds = new Set<Id>();
    for (TransitionRequest request : requests) {
      if (
        allOrNone == true &&
        (request == null ||
        request.requestId == null ||
        requestIds.contains(request.requestId))
      ) {
        throw new StateTransitionException(
          'Each return request must have a unique Id.'
        );
      }
      requestIds.add(request.requestId);
    }

    Map<Id, Return_Request__c> requestMap = new Map<Id, Return_Request__c>(
      [
        SELECT Id, Status__c, Required_Approval_Level__c
        FROM Return_Request__c
        WHERE Id IN :requestIds
        FOR UPDATE
      ]
    );

    List<Return_Request__c> requestsToUpdate = new List<Return_Request__c>();

    for (TransitionRequest transitionRequest : requests) {
      Return_Request__c requestRecord = requestMap.get(
        transitionRequest.requestId
      );

      if (requestRecord == null) {
        if (allOrNone == true) {
          throw new StateTransitionException('Request not found.');
        }
        results.add(
          new TransitionResult(
            transitionRequest.requestId,
            false,
            'Request not found.'
          )
        );
        continue;
      }

      try {
        StateTransitionValidator.validate(
          requestRecord.Status__c,
          transitionRequest.targetStatus
        );

        requestRecord.Status__c = transitionRequest.targetStatus;

        if (
          transitionRequest.targetStatus ==
          SmartReturnConstants.STATUS_PENDING_APPROVAL
        ) {
          requestRecord.Approval_Due_At__c = System.now()
            .addHours(SmartReturnConfigService.getApprovalTimeoutHours());
        }

        if (String.isNotBlank(transitionRequest.requiredApprovalLevel)) {
          requestRecord.Required_Approval_Level__c = transitionRequest.requiredApprovalLevel;
        }
        if (String.isNotBlank(transitionRequest.rejectReason)) {
          requestRecord.Rejection_Reason__c = transitionRequest.rejectReason;
        }
        if (String.isNotBlank(transitionRequest.internalStaffNote)) {
          requestRecord.Internal_Notes__c = transitionRequest.internalStaffNote;
        }
        requestsToUpdate.add(requestRecord);
      } catch (Exception ex) {
        if (allOrNone == true) {
          throw ex;
        }
        results.add(
          new TransitionResult(requestRecord.Id, false, ex.getMessage())
        );
      }
    }

    if (!requestsToUpdate.isEmpty()) {
      Savepoint checkpoint = allOrNone == true ? Database.setSavepoint() : null;
      try {
        Database.SaveResult[] saveResults = Database.update(
          requestsToUpdate,
          allOrNone
        );

        for (Integer index = 0; index < saveResults.size(); index++) {
          if (saveResults[index].isSuccess()) {
            results.add(
              new TransitionResult(requestsToUpdate[index].Id, true, 'SUCCESS')
            );
          } else {
            results.add(
              new TransitionResult(
                requestsToUpdate[index].Id,
                false,
                saveResults[index].getErrors()[0].getMessage()
              )
            );
          }
        }

        LogService.info(
          requestsToUpdate,
          'Bulk state transition completed.',
          'StateTransitionService',
          'BULK_UPDATE'
        );

        LogService.insertLogs();
      } catch (Exception ex) {
        if (allOrNone != true) {
          throw ex;
        }
        Database.rollback(checkpoint);
        throw new StateTransitionException(
          'Could not transition return requests: ' + ex.getMessage(),
          ex
        );
      }
    }

    return results;
  }

  public class StateTransitionException extends Exception {
  }
}
