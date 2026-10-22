public inherited sharing class ReturnRequestTriggerHandler {
  public static void beforeUpdate(
    List<Return_Request__c> newRecords,
    Map<Id, Return_Request__c> oldRecordsById
  ) {
    for (Return_Request__c newRecord : newRecords) {
      Return_Request__c oldRecord = oldRecordsById.get(newRecord.Id);

      if (oldRecord == null) {
        continue;
      }

      if (oldRecord.Status__c == newRecord.Status__c) {
        continue;
      }

      try {
        StateTransitionValidator.validate(
          oldRecord.Status__c,
          newRecord.Status__c
        );
      } catch (StateTransitionValidator.StateTransitionException ex) {
        newRecord.Status__c.addError(ex.getMessage());
      }
    }
  }
}
