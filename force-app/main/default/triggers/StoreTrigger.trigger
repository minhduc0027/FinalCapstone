trigger StoreTrigger on Store__c(
  before insert,
  before update,
  before delete,
  after insert,
  after update,
  after delete,
  after undelete
) {
  StoreTriggerHandler.handle();
}
