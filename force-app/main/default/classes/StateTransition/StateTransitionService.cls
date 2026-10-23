public inherited sharing class StateTransitionService {
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
    List<TransitionResult> results = new List<TransitionResult>();

    if (requests == null || requests.isEmpty()) {
      return results;
    }

    Set<Id> requestIds = new Set<Id>();
    for (TransitionRequest request : requests) {
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
        results.add(
          new TransitionResult(requestRecord.Id, false, ex.getMessage())
        );
      }
    }

    if (!requestsToUpdate.isEmpty()) {
      Database.SaveResult[] saveResults = Database.update(
        requestsToUpdate,
        false
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
        new List<SObject>(requestsToUpdate),
        'Bulk state transition completed.',
        'StateTransitionService',
        'BULK_UPDATE'
      );

      LogService.insertLogs();
    }

    return results;
  }

  public class StateTransitionException extends Exception {
  }
}
