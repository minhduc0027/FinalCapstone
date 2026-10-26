public inherited sharing class UserTriggerHandler {
  public static void handle() {
    if (
      Trigger.operationType != System.TriggerOperation.AFTER_INSERT &&
      Trigger.operationType != System.TriggerOperation.AFTER_UPDATE
    )
      return;

    Set<String> changedStoreCodes = new Set<String>();
    for (User userRecord : (List<User>) Trigger.new) {
      User previous = Trigger.isUpdate
        ? (User) Trigger.oldMap.get(userRecord.Id)
        : null;
      if (
        previous != null &&
        userRecord.Store_Code__c == previous.Store_Code__c &&
        userRecord.IsActive == previous.IsActive
      )
        continue;

      if (previous != null && String.isNotBlank(previous.Store_Code__c)) {
        changedStoreCodes.add(previous.Store_Code__c);
      }
      if (userRecord.IsActive && String.isNotBlank(userRecord.Store_Code__c)) {
        changedStoreCodes.add(userRecord.Store_Code__c);
      }
    }

    if (!changedStoreCodes.isEmpty()) {
      Database.executeBatch(
        new ReturnRequestShareRebuildBatch(null, changedStoreCodes),
        200
      );
    }
  }
}
