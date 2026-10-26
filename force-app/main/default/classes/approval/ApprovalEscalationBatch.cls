public with sharing class ApprovalEscalationBatch implements Database.Batchable<SObject>, Database.RaisesPlatformEvents {
  //===================================================
  // Escalation Route
  // - Pending Approval -> Pending Approval (escalation)
  //===================================================
  public Database.QueryLocator start(Database.BatchableContext context) {
    Integer approvalTimeoutHours = SmartReturnConfigService.getApprovalTimeoutHours();
    return Database.getQueryLocator(
      [
        SELECT
          Id,
          Required_Approval_Level__c,
          Store__c,
          Store__r.Region_Manager__c
        FROM Return_Request__c
        WHERE
          Status__c = :SmartReturnConstants.STATUS_PENDING_APPROVAL
          AND Required_Approval_Level__c = :SmartReturnConstants.APPROVAL_CHT
          AND Approval_Due_At__c <= :System.now()
      ]
    );
  }

  public void execute(Database.BatchableContext context, List<SObject> scope) {
    List<Return_Request__c> requestsToUpdate = (List<Return_Request__c>) scope;
    for (Return_Request__c request : requestsToUpdate) {
      request.Required_Approval_Level__c = SmartReturnConstants.APPROVAL_QLV;
      request.ApproverId__c = request.Store__r.Region_Manager__c;
    }
    LogService.warn(
      requestsToUpdate,
      'ApprovalTimeout: Escalating approval level from CHT to QLV',
      'ApprovalEscalationBatch',
      'ESCALATE_APPROVAL'
    );

    Database.SaveResult[] results = Database.update(requestsToUpdate, false);
    for (Integer i = 0; i < results.size(); i++) {
      if (!results[i].isSuccess()) {
        LogService.error(
          new List<Return_Request__c>{ requestsToUpdate[i] },
          'ApprovalTimeout: Failed to escalate approval level from CHT to QLV. Error: ' +
          results[i].getErrors()[0].getMessage(),
          'ApprovalEscalationBatch',
          'ESCALATE_APPROVAL'
        );
      }
    }
    LogService.insertLogs();
  }

  public void finish(Database.BatchableContext context) {
  }
}
