/** Creates complete request fixtures independently of the validating user's FLS. */
@IsTest
public with sharing class ReturnRequestTestDataFactory {
  private static Integer storeSequence = 0;

  /** Creates a test actor explicitly permitted to persist a rejection reason. */
  public static void createApprover() {
    User actor = new User(
      Alias = 'rrapp',
      LastName = 'Return Request Test Approver',
      Email = 'return.approver@example.invalid',
      Username = 'return.approver.' +
        Crypto.getRandomLong() +
        '@example.invalid',
      ProfileId = UserInfo.getProfileId(),
      TimeZoneSidKey = 'Asia/Ho_Chi_Minh',
      LocaleSidKey = 'en_US',
      EmailEncodingKey = 'UTF-8',
      LanguageLocaleKey = 'en_US'
    );
    insert as system actor;

    PermissionSet permissions = new PermissionSet(
      Name = 'Return_Request_Test_Rejection',
      Label = 'Return Request Test Rejection'
    );
    insert as system permissions;
    insert as system new ObjectPermissions(
      ParentId = permissions.Id,
      SObjectType = 'Return_Request__c',
      PermissionsRead = true,
      PermissionsEdit = true
    );
    insert as system new FieldPermissions(
      ParentId = permissions.Id,
      SObjectType = 'Return_Request__c',
      Field = 'Return_Request__c.Rejection_Reason__c',
      PermissionsRead = true,
      PermissionsEdit = true
    );
    insert as system new PermissionSetAssignment(
      AssigneeId = actor.Id,
      PermissionSetId = permissions.Id
    );
  }

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
