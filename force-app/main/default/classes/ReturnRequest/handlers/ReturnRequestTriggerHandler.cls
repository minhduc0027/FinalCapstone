public inherited sharing class ReturnRequestTriggerHandler {
  public static void handle() {
    List<Return_Request__c> records = (List<Return_Request__c>) Trigger.new;
    Map<Id, Return_Request__c> oldRecordsById = (Map<Id, Return_Request__c>) Trigger.oldMap;

    switch on Trigger.operationType {
      when Trigger.BEFORE_INSERT {
        return;
      }
      when Trigger.BEFORE_UPDATE {
        StateTransitionService.validateBeforeUpdate(records, oldRecordsById);
      }
      when Trigger.AFTER_INSERT {
        return;
      }
      when Trigger.AFTER_UPDATE {
        return;
      }
    }
  }
}
