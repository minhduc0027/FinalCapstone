public inherited sharing class ReturnRequestTriggerHandler {
  public static void handle() {
    switch on Trigger.operationType {
      when BEFORE_INSERT {
        return;
      }
      when BEFORE_UPDATE {
        StateTransitionService.validateBeforeUpdate(
          (List<Return_Request__c>) Trigger.new,
          (Map<Id, Return_Request__c>) Trigger.oldMap
        );
      }
      when AFTER_INSERT {
        return;
      }
      when AFTER_UPDATE {
        return;
      }
    }
  }
}
