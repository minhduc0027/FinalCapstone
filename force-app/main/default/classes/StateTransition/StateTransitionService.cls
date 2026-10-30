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
    transition(requestId, targetStatus, requiredApprovalLevel, null);
  }

  /** Transitions a request and persists the rejection reason in the same update. */
  public static void transition(
    Id requestId,
    String targetStatus,
    String requiredApprovalLevel,
    String rejectionReason
  ) {
    if (requestId == null) {
      throw new StateTransitionException('Return Request Id is required.');
    }
    Return_Request__c requestRecord = [
      SELECT Id, Status__c
      FROM Return_Request__c
      WHERE Id = :requestId
      WITH USER_MODE
      LIMIT 1
      FOR UPDATE
    ];
    String oldStatus = requestRecord.Status__c;
    StateTransitionValidator.validate(oldStatus, targetStatus);
    requestRecord.Status__c = targetStatus;
    if (String.isNotBlank(requiredApprovalLevel)) {
      requestRecord.Required_Approval_Level__c = requiredApprovalLevel;
    }

    if (rejectionReason != null)
      requestRecord.Rejection_Reason__c = rejectionReason;

    try {
      // Entry-point services authorize the workflow; status remains read-only in user APIs.
      update as system requestRecord;
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
        WITH USER_MODE
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

        if (String.isNotBlank(transitionRequest.requiredApprovalLevel)) {
          requestRecord.Required_Approval_Level__c = transitionRequest.requiredApprovalLevel;
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
          allOrNone,
          AccessLevel.SYSTEM_MODE
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

  public static List<TransitionResult> transitionApprovalBulk(
    List<ApprovalTransitionRequest> requests
  ) {
    List<TransitionResult> results = new List<TransitionResult>();

    if (requests == null || requests.isEmpty()) {
      return results;
    }

    Set<Id> requestIds = new Set<Id>();
    Map<Id, ApprovalTransitionRequest> inputById = new Map<Id, ApprovalTransitionRequest>();

    for (ApprovalTransitionRequest input : requests) {
      if (input == null || input.requestId == null) {
        results.add(
          new TransitionResult(null, false, 'Return Request Id is required.')
        );
        continue;
      }

      if (inputById.containsKey(input.requestId)) {
        results.add(
          new TransitionResult(
            input.requestId,
            false,
            'Duplicate Return Request Id.'
          )
        );
        continue;
      }

      requestIds.add(input.requestId);
      inputById.put(input.requestId, input);
    }

    if (requestIds.isEmpty()) {
      return results;
    }

    Map<Id, Return_Request__c> recordsById = new Map<Id, Return_Request__c>(
      [
        SELECT Id, Status__c, Required_Approval_Level__c
        FROM Return_Request__c
        WHERE Id IN :requestIds
        WITH USER_MODE
        FOR UPDATE
      ]
    );

    List<Return_Request__c> recordsToUpdate = new List<Return_Request__c>();

    List<Id> updateOrder = new List<Id>();

    for (Id requestId : inputById.keySet()) {
      ApprovalTransitionRequest input = inputById.get(requestId);

      Return_Request__c storedRecord = recordsById.get(requestId);

      if (storedRecord == null) {
        results.add(
          new TransitionResult(requestId, false, 'Return Request not found.')
        );
        continue;
      }

      try {
        StateTransitionValidator.validate(
          storedRecord.Status__c,
          input.targetStatus
        );

        Return_Request__c sparseUpdate = new Return_Request__c(
          Id = requestId,
          Status__c = input.targetStatus
        );

        if (String.isNotBlank(input.requiredApprovalLevel)) {
          sparseUpdate.Required_Approval_Level__c = input.requiredApprovalLevel;
        }

        if (String.isNotBlank(input.rejectionReason)) {
          sparseUpdate.Rejection_Reason__c = input.rejectionReason;
        }

        if (String.isNotBlank(input.internalNote)) {
          sparseUpdate.Internal_Notes__c = input.internalNote;
        }

        if (
          input.targetStatus == SmartReturnConstants.STATUS_PENDING_APPROVAL
        ) {
          sparseUpdate.Approval_Due_At__c = System.now()
            .addHours(SmartReturnConfigService.getApprovalTimeoutHours());
        }

        recordsToUpdate.add(sparseUpdate);
        updateOrder.add(requestId);
      } catch (Exception ex) {
        results.add(new TransitionResult(requestId, false, ex.getMessage()));
      }
    }

    if (recordsToUpdate.isEmpty()) {
      return results;
    }

    Database.SaveResult[] saveResults = Database.update(
      recordsToUpdate,
      false,
      AccessLevel.SYSTEM_MODE
    );

    List<SObject> successfulRecords = new List<SObject>();

    for (Integer index = 0; index < saveResults.size(); index++) {
      Id requestId = updateOrder[index];

      if (saveResults[index].isSuccess()) {
        results.add(new TransitionResult(requestId, true, 'SUCCESS'));

        successfulRecords.add(recordsToUpdate[index]);
      } else {
        results.add(
          new TransitionResult(
            requestId,
            false,
            joinApprovalErrors(saveResults[index].getErrors())
          )
        );
      }
    }

    if (!successfulRecords.isEmpty()) {
      LogService.info(
        successfulRecords,
        'Approval bulk state transition completed.',
        'StateTransitionService',
        'APPROVAL_BULK_UPDATE'
      );

      LogService.insertLogs();
    }

    return results;
  }

  private static String joinApprovalErrors(Database.Error[] errors) {
    List<String> messages = new List<String>();

    for (Database.Error errorValue : errors) {
      messages.add(errorValue.getMessage());
    }

    return String.join(messages, '; ');
  }

  public class ApprovalTransitionRequest {
    public Id requestId;
    public String targetStatus;
    public String requiredApprovalLevel;
    public String rejectionReason;
    public String internalNote;

    public ApprovalTransitionRequest(
      Id requestId,
      String targetStatus,
      String requiredApprovalLevel,
      String rejectionReason,
      String internalNote
    ) {
      this.requestId = requestId;
      this.targetStatus = targetStatus;
      this.requiredApprovalLevel = requiredApprovalLevel;
      this.rejectionReason = rejectionReason;
      this.internalNote = internalNote;
    }
  }

  public class StateTransitionException extends Exception {
  }
}
