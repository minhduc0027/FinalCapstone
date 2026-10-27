public without sharing class ReturnRequestSharingService {
  public static void refresh(List<Return_Request__c> requests) {
    if (requests == null || requests.isEmpty())
      return;

    Set<Id> requestIds = new Set<Id>();
    Set<Id> storeIds = new Set<Id>();
    for (Return_Request__c request : requests) {
      requestIds.add(request.Id);
      if (request.Store__c != null)
        storeIds.add(request.Store__c);
    }

    Map<Id, Store__c> stores = new Map<Id, Store__c>(
      [
        SELECT Id, Store_Code__c, Store_Manager__c, Region_Manager__c
        FROM Store__c
        WHERE Id IN :storeIds
      ]
    );
    Set<String> storeCodes = new Set<String>();
    for (Store__c store : stores.values()) {
      if (String.isNotBlank(store.Store_Code__c))
        storeCodes.add(store.Store_Code__c);
    }

    Map<String, Set<Id>> staffByStoreCode = new Map<String, Set<Id>>();
    for (User staff : [
      SELECT Id, Store_Code__c
      FROM User
      WHERE IsActive = TRUE AND Store_Code__c IN :storeCodes
      WITH SYSTEM_MODE
    ]) {
      if (!staffByStoreCode.containsKey(staff.Store_Code__c)) {
        staffByStoreCode.put(staff.Store_Code__c, new Set<Id>());
      }
      staffByStoreCode.get(staff.Store_Code__c).add(staff.Id);
    }

    Map<Id, Map<Id, Return_Request__Share>> existingByRequest = new Map<Id, Map<Id, Return_Request__Share>>();
    for (Return_Request__Share share : [
      SELECT Id, ParentId, UserOrGroupId, AccessLevel
      FROM Return_Request__Share
      WHERE ParentId IN :requestIds AND RowCause = 'SmartReturn_Access__c'
    ]) {
      if (!existingByRequest.containsKey(share.ParentId)) {
        existingByRequest.put(
          share.ParentId,
          new Map<Id, Return_Request__Share>()
        );
      }
      existingByRequest.get(share.ParentId).put(share.UserOrGroupId, share);
    }

    List<Return_Request__Share> toInsert = new List<Return_Request__Share>();
    List<Return_Request__Share> toDelete = new List<Return_Request__Share>();
    for (Return_Request__c request : requests) {
      Store__c store = stores.get(request.Store__c);
      Set<Id> recipients = new Set<Id>();
      if (store != null) {
        Set<Id> staff = staffByStoreCode.get(store.Store_Code__c);
        if (staff != null)
          recipients.addAll(staff);
        if (store.Store_Manager__c != null)
          recipients.add(store.Store_Manager__c);
        if (store.Region_Manager__c != null)
          recipients.add(store.Region_Manager__c);
      }
      recipients.remove(request.OwnerId);

      Map<Id, Return_Request__Share> existing = existingByRequest.get(
        request.Id
      );
      if (existing == null)
        existing = new Map<Id, Return_Request__Share>();

      for (Id recipientId : recipients) {
        if (existing.containsKey(recipientId)) {
          existing.remove(recipientId);
          continue;
        }
        toInsert.add(
          new Return_Request__Share(
            ParentId = request.Id,
            UserOrGroupId = recipientId,
            AccessLevel = 'Edit',
            RowCause = Schema.Return_Request__Share.RowCause.SmartReturn_Access__c
          )
        );
      }
      toDelete.addAll(existing.values());
    }

    if (!toDelete.isEmpty())
      delete toDelete;
    if (!toInsert.isEmpty())
      insert toInsert;
  }
}
