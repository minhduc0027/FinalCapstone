trigger ReturnRequestTrigger on Return_Request__c(
  before insert,
  before update,
  before delete,
  after insert,
  after update,
  after delete,
  after undelete
) {
  ReturnRequestTriggerHandler.handle();
}
