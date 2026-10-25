@IsTest
private class ReturnRequestSharingTests {
  @TestSetup
  static void users() {
    Id profileId = [
      SELECT Id
      FROM Profile
      WHERE Name = 'Minimum Access - Salesforce'
      LIMIT 1
    ]
    .Id;
    List<User> actors = new List<User>();
    for (
      String role : new List<String>{ 'STAFFA', 'STAFFB', 'REGION', 'SERVICE' }
    ) {
      actors.add(
        new User(
          Alias = role.left(8),
          LastName = role,
          Email = role.toLowerCase() + '@example.invalid',
          Username = role.toLowerCase() +
            '.' +
            Crypto.getRandomLong() +
            '@example.invalid',
          ProfileId = profileId,
          TimeZoneSidKey = 'Asia/Ho_Chi_Minh',
          LocaleSidKey = 'en_US',
          EmailEncodingKey = 'UTF-8',
          LanguageLocaleKey = 'en_US',
          Store_Code__c = role == 'STAFFA'
            ? 'STORE-A'
            : role == 'STAFFB' ? 'STORE-B' : null
        )
      );
    }
    insert actors;

    Map<String, Id> permissionIds = new Map<String, Id>();
    for (PermissionSet permission : [
      SELECT Id, Name
      FROM PermissionSet
      WHERE
        Name IN (
          'SmartReturn_Return_Operations',
          'SmartReturn_Customer_Service'
        )
    ]) {
      permissionIds.put(permission.Name, permission.Id);
    }
    List<PermissionSetAssignment> assignments = new List<PermissionSetAssignment>();
    for (User actor : actors) {
      assignments.add(
        new PermissionSetAssignment(
          AssigneeId = actor.Id,
          PermissionSetId = actor.LastName == 'SERVICE'
            ? permissionIds.get('SmartReturn_Customer_Service')
            : permissionIds.get('SmartReturn_Return_Operations')
        )
      );
    }
    insert assignments;
  }

  @IsTest
  static void storeRegionAndServiceVisibility() {
    Map<String, User> actors = new Map<String, User>();
    for (User actor : [
      SELECT Id, LastName
      FROM User
      WHERE LastName IN ('STAFFA', 'STAFFB', 'REGION', 'SERVICE')
    ]) {
      actors.put(actor.LastName, actor);
    }
    Account customer = new Account(Name = 'Sharing Customer');
    insert customer;
    List<Store__c> stores = new List<Store__c>{
      new Store__c(
        Name = 'Store A',
        Store_Code__c = 'STORE-A',
        Region__c = 'Nam',
        Region_Manager__c = actors.get('REGION').Id
      ),
      new Store__c(
        Name = 'Store B',
        Store_Code__c = 'STORE-B',
        Region__c = 'Nam',
        Region_Manager__c = actors.get('REGION').Id
      )
    };
    insert stores;
    List<Order> orders = new List<Order>();
    for (Store__c store : stores) {
      orders.add(
        new Order(
          AccountId = customer.Id,
          EffectiveDate = Date.today(),
          Status = 'Draft',
          Store__c = store.Id
        )
      );
    }
    insert orders;
    List<Return_Request__c> requests = new List<Return_Request__c>();
    for (Order orderRecord : orders) {
      requests.add(
        new Return_Request__c(
          Order__c = orderRecord.Id,
          Customer__c = customer.Id,
          Store__c = orderRecord.Store__c,
          Source_Channel__c = SmartReturnConstants.SOURCE_STORE,
          Status__c = SmartReturnConstants.STATUS_NEW
        )
      );
    }
    insert requests;

    System.runAs(actors.get('STAFFA')) {
      System.assertEquals(1, [SELECT COUNT() FROM Return_Request__c]);
    }
    System.runAs(actors.get('STAFFB')) {
      System.assertEquals(1, [SELECT COUNT() FROM Return_Request__c]);
    }
    System.runAs(actors.get('REGION')) {
      System.assertEquals(2, [SELECT COUNT() FROM Return_Request__c]);
    }
    System.runAs(actors.get('SERVICE')) {
      System.assertEquals(2, [SELECT COUNT() FROM Return_Request__c]);
      System.assertEquals(
        false,
        Return_Request__c.SObjectType.getDescribe().isUpdateable()
      );
    }

    Test.startTest();
    System.runAs(new User(Id = UserInfo.getUserId())) {
      update new User(Id = actors.get('STAFFA').Id, Store_Code__c = 'STORE-B');
    }
    Test.stopTest();

    System.runAs(actors.get('STAFFA')) {
      List<Return_Request__c> visible = [
        SELECT Store__c
        FROM Return_Request__c
      ];
      System.assertEquals(1, visible.size());
      System.assertEquals(stores[1].Id, visible[0].Store__c);
    }
  }
}
