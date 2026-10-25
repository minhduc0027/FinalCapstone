@IsTest
public class PortalTestDataFactory {
  public static void setupData() {
    UserRole role = new UserRole(Name = 'Portal fixture owner');
    insert role;
    User owner = actor('Portal Owner', UserInfo.getProfileId());
    owner.UserRoleId = role.Id;
    User visitor = actor(
      'Portal Guest Actor',
      [
        SELECT Id
        FROM Profile
        WHERE Name = 'Minimum Access - Salesforce'
        LIMIT 1
      ]
      .Id
    );
    insert new List<User>{ owner, visitor };
    insert new List<PermissionSetAssignment>{
      new PermissionSetAssignment(
        AssigneeId = visitor.Id,
        PermissionSetId = [
          SELECT Id
          FROM PermissionSet
          WHERE Name = 'SmartReturn_Portal_Guest_Access'
          LIMIT 1
        ]
        .Id
      ),
      new PermissionSetAssignment(
        AssigneeId = owner.Id,
        PermissionSetId = [
          SELECT Id
          FROM PermissionSet
          WHERE Name = 'SmartReturn_Return_Operations'
          LIMIT 1
        ]
        .Id
      )
    };
    List<Contact> contacts;
    System.runAs(owner) {
      List<Account> customers = new List<Account>{
        new Account(Name = 'Portal Customer A', Phone = '+84 (090) 123 4567'),
        new Account(Name = 'Portal Customer B', Phone = '0907654321')
      };
      insert customers;
      contacts = new List<Contact>{
        new Contact(
          LastName = 'Portal A',
          AccountId = customers[0].Id,
          Email = 'portal.a@example.invalid'
        ),
        new Contact(
          LastName = 'Portal B',
          AccountId = customers[1].Id,
          Email = 'portal.b@example.invalid'
        )
      };
      insert contacts;
      Store__c store = new Store__c(
        Name = 'Portal Store',
        Store_Code__c = 'EC-TEST',
        Region__c = 'Nam'
      );
      insert store;
      List<Order> orders = new List<Order>();
      for (Account customer : customers) {
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
      for (Integer i = 0; i < 4; i++) {
        Integer customerIndex = i < 3 ? 0 : 1;
        requests.add(
          new Return_Request__c(
            Customer__c = customers[customerIndex].Id,
            Order__c = orders[customerIndex].Id,
            Store__c = store.Id,
            Source_Channel__c = SmartReturnConstants.SOURCE_APP,
            Status__c = SmartReturnConstants.STATUS_NEW,
            Estimated_Refund_Amount__c = 2490000,
            Internal_Notes__c = 'PRIVATE STAFF NOTE'
          )
        );
      }
      insert as system requests;
      Product2 product = new Product2(
        Name = 'Nồi chiên không dầu',
        ProductCode = 'EC-PRODUCT',
        IsActive = true
      );
      insert product;
      List<Return_Request_Line__c> lines = new List<Return_Request_Line__c>();
      for (Return_Request__c request : requests) {
        lines.add(
          new Return_Request_Line__c(
            Return_Request__c = request.Id,
            Product__c = product.Id,
            Requested_Quantity__c = 2
          )
        );
      }
      insert as system lines;
    }
    System.runAs(new User(Id = UserInfo.getUserId())) {
      Id profileId = [
        SELECT Id
        FROM Profile
        WHERE Name = 'SmartReturn Customer'
        LIMIT 1
      ]
      .Id;
      List<User> customers = new List<User>();
      for (Contact contact : contacts) {
        User customer = actor(contact.LastName, profileId);
        customer.ContactId = contact.Id;
        customers.add(customer);
      }
      insert customers;
      Id permissionId = [
        SELECT Id
        FROM PermissionSet
        WHERE Name = 'SmartReturn_Portal_Customer'
        LIMIT 1
      ]
      .Id;
      List<PermissionSetAssignment> assignments = new List<PermissionSetAssignment>();
      for (User customer : customers)
        assignments.add(
          new PermissionSetAssignment(
            AssigneeId = customer.Id,
            PermissionSetId = permissionId
          )
        );
      insert assignments;
    }
  }

  private static User actor(String lastName, Id profileId) {
    String uniquePart = String.valueOf(Crypto.getRandomLong()).replace('-', '');
    return new User(
      Alias = 'ecuser',
      LastName = lastName,
      Email = 'portal@example.invalid',
      Username = 'ec.' + uniquePart + '@example.invalid',
      CommunityNickname = 'ec' + uniquePart,
      ProfileId = profileId,
      TimeZoneSidKey = 'Asia/Ho_Chi_Minh',
      LocaleSidKey = 'vi_VN',
      EmailEncodingKey = 'UTF-8',
      LanguageLocaleKey = 'en_US'
    );
  }
}
