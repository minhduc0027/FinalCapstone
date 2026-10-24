trigger ReturnRequestTrigger on Return_Request__c(
  before insert,
  before update,
  after insert,
  after update
) {
  ReturnRequestTriggerHandler.handle();
}
