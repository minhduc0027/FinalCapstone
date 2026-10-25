/** Creates complete request fixtures independently of the validating user's FLS. */
@IsTest
public with sharing class ReturnRequestTestDataFactory {
  private static Integer storeSequence = 0;

  /** Builds unsaved requests with persisted customer, order, and store records. */
  public static List<Return_Request__c> requests(Integer count, Id customerId) {
    if (customerId == null) {
      Account customer = new Account(Name = 'Return request test customer');
      insert as system customer;
      customerId = customer.Id;
    }
    storeSequence++;
    Store__c store = new Store__c(
      Name = 'Return request test store',
      Store_Code__c = 'RR-TEST-' + storeSequence,
      Store_Manager__c = UserInfo.getUserId(),
      Region_Manager__c = UserInfo.getUserId()
    );
    insert as system store;
    Order orderRecord = new Order(
      AccountId = customerId,
      Store__c = store.Id,
      EffectiveDate = Date.today(),
      Status = 'Draft'
    );
    insert as system orderRecord;

    List<Return_Request__c> requests = new List<Return_Request__c>();
    for (Integer i = 0; i < count; i++) {
      requests.add(
        new Return_Request__c(
          Customer__c = customerId,
          Order__c = orderRecord.Id,
          Store__c = store.Id,
          Source_Channel__c = SmartReturnConstants.SOURCE_STORE,
          Status__c = SmartReturnConstants.STATUS_NEW
        )
      );
    }
    return requests;
  }
}
