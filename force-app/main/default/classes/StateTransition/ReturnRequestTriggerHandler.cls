public inherited sharing class ReturnRequestTriggerHandler {
  public static void beforeUpdate(
    List<Case> newRecords,
    Map<Id, Case> oldRecordsById
  ) {
    for (Case newRecord : newRecords) {
      Case oldRecord = oldRecordsById.get(newRecord.Id);

      if (oldRecord == null) {
        continue;
      }

      if (oldRecord.Status == newRecord.Status) {
        continue;
      }

      try {
        StateTransitionValidator.validate(oldRecord.Status, newRecord.Status);
      } catch (StateTransitionValidator.StateTransitionException ex) {
        newRecord.Status.addError(ex.getMessage());
      }
    }
  }
}
