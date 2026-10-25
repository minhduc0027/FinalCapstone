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
        ReturnRequestSharingService.refresh(
          (List<Return_Request__c>) Trigger.new
        );
      }
      when AFTER_UPDATE {
        List<Return_Request__c> changedStores = new List<Return_Request__c>();
        for (
          Return_Request__c request : (List<Return_Request__c>) Trigger.new
        ) {
          Return_Request__c previous = (Return_Request__c) Trigger.oldMap
            .get(request.Id);
          if (
            request.Store__c != previous.Store__c ||
            request.OwnerId != previous.OwnerId
          ) {
            changedStores.add(request);
          }
        }
        ReturnRequestSharingService.refresh(changedStores);
      }
    }
  }
}
