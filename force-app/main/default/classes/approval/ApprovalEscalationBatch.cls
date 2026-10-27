public with sharing class ApprovalEscalationBatch implements Database.Batchable<SObject>, Database.RaisesPlatformEvents {
  public Database.QueryLocator start(Database.BatchableContext context) {
    Datetime nowValue = System.now();

    return Database.getQueryLocator(
      [
        SELECT
          Id,
          Status__c,
          Required_Approval_Level__c,
          ApproverId__c,
          Approval_Due_At__c,
          Store__c,
          Store__r.Region_Manager__c
        FROM Return_Request__c
        WHERE
          Status__c = :SmartReturnConstants.STATUS_PENDING_APPROVAL
          AND Required_Approval_Level__c = :SmartReturnConstants.APPROVAL_CHT
          AND Approval_Due_At__c != NULL
          AND Approval_Due_At__c <= :nowValue
      ]
    );
  }

  public void execute(Database.BatchableContext context, List<SObject> scope) {
    List<Return_Request__c> requests = (List<Return_Request__c>) scope;

    List<Return_Request__c> updates = new List<Return_Request__c>();

    for (Return_Request__c requestRecord : requests) {
      Id regionalManagerId = requestRecord.Store__r == null
        ? null
        : requestRecord.Store__r.Region_Manager__c;

      if (regionalManagerId == null) {
        LogService.error(
          new List<SObject>{ requestRecord },
          'Cannot escalate because Regional Manager ' + 'is not configured.',
          'ApprovalEscalationBatch',
          'ESCALATE_APPROVAL'
        );

        continue;
      }

      updates.add(
        new Return_Request__c(
          Id = requestRecord.Id,
          Required_Approval_Level__c = SmartReturnConstants.APPROVAL_QLV,
          ApproverId__c = regionalManagerId,
          Approval_Due_At__c = null
        )
      );
    }

    if (!updates.isEmpty()) {
      Database.SaveResult[] saveResults = Database.update(updates, false);

      for (Integer index = 0; index < saveResults.size(); index++) {
        if (saveResults[index].isSuccess()) {
          LogService.warn(
            new List<SObject>{ updates[index] },
            'Approval timeout exceeded. ' + 'Escalated from CHT to QLV.',
            'ApprovalEscalationBatch',
            'ESCALATE_APPROVAL'
          );
        } else {
          LogService.error(
            new List<SObject>{ updates[index] },
            joinErrors(saveResults[index].getErrors()),
            'ApprovalEscalationBatch',
            'ESCALATE_APPROVAL'
          );
        }
      }
    }

    LogService.insertLogs();
  }

  public void finish(Database.BatchableContext context) {
  }

  private static String joinErrors(Database.Error[] errors) {
    List<String> messages = new List<String>();

    for (Database.Error errorValue : errors) {
      messages.add(errorValue.getMessage());
    }

    return String.join(messages, '; ');
  }
}
