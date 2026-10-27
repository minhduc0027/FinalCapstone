public inherited sharing class StoreTriggerHandler {
  public static void handle() {
    if (Trigger.operationType != System.TriggerOperation.AFTER_UPDATE)
      return;

    Set<Id> changedStoreIds = new Set<Id>();
    for (Store__c store : (List<Store__c>) Trigger.new) {
      Store__c previous = (Store__c) Trigger.oldMap.get(store.Id);
      if (
        store.Store_Code__c != previous.Store_Code__c ||
        store.Store_Manager__c != previous.Store_Manager__c ||
        store.Region_Manager__c != previous.Region_Manager__c
      ) {
        changedStoreIds.add(store.Id);
      }
    }

    if (!changedStoreIds.isEmpty()) {
      Database.executeBatch(
        new ReturnRequestShareRebuildBatch(changedStoreIds, null),
        200
      );
    }
  }
}
