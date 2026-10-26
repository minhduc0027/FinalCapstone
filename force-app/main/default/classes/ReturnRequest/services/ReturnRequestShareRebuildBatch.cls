public without sharing class ReturnRequestShareRebuildBatch implements Database.Batchable<SObject> {
  private Set<Id> storeIds;
  private Set<String> storeCodes;

  public ReturnRequestShareRebuildBatch(
    Set<Id> storeIds,
    Set<String> storeCodes
  ) {
    this.storeIds = storeIds == null ? new Set<Id>() : storeIds;
    this.storeCodes = storeCodes == null ? new Set<String>() : storeCodes;
  }

  public Database.QueryLocator start(Database.BatchableContext context) {
    return Database.getQueryLocator(
      [
        SELECT Id, Store__c, OwnerId
        FROM Return_Request__c
        WHERE Store__c IN :storeIds OR Store__r.Store_Code__c IN :storeCodes
      ]
    );
  }

  public void execute(Database.BatchableContext context, List<SObject> scope) {
    ReturnRequestSharingService.refresh((List<Return_Request__c>) scope);
  }

  public void finish(Database.BatchableContext context) {
  }
}
