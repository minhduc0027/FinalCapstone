trigger StoreTrigger on Store__c(after update) {
  StoreTriggerHandler.handle();
}
