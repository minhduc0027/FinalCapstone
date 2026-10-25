@IsTest
public with sharing class RefundTestDataFactory {
  public static User grantProcessor() {
    User actor = new User(
      Alias = 'rfproc',
      LastName = 'Refund Test Processor',
      Email = 'refund@example.invalid',
      Username = 'refund.' + Crypto.getRandomLong() + '@example.invalid',
      ProfileId = UserInfo.getProfileId(),
      TimeZoneSidKey = 'Asia/Ho_Chi_Minh',
      LocaleSidKey = 'vi_VN',
      EmailEncodingKey = 'UTF-8',
      LanguageLocaleKey = 'en_US'
    );
    insert actor;
    PermissionSet permissions = [
      SELECT Id
      FROM PermissionSet
      WHERE Name = 'SmartReturn_Refund_Processor'
    ];
    insert new PermissionSetAssignment(
      AssigneeId = actor.Id,
      PermissionSetId = permissions.Id
    );
    return actor;
  }
  public static User accountant() {
    User actor = new User(
      Alias = 'rfacct',
      LastName = 'Refund Test Accountant',
      Email = 'accounting@example.invalid',
      Username = String.join(
        new List<String>{
          'accounting',
          String.valueOf(Crypto.getRandomLong()),
          '@example.invalid'
        },
        '.'
      ),
      ProfileId = UserInfo.getProfileId(),
      TimeZoneSidKey = 'Asia/Ho_Chi_Minh',
      LocaleSidKey = 'vi_VN',
      EmailEncodingKey = 'UTF-8',
      LanguageLocaleKey = 'en_US'
    );
    insert actor;
    PermissionSet permissions = [
      SELECT Id
      FROM PermissionSet
      WHERE Name = 'SmartReturn_Refund_Accounting'
    ];
    insert new PermissionSetAssignment(
      AssigneeId = actor.Id,
      PermissionSetId = permissions.Id
    );
    return actor;
  }
  public static User processor() {
    return [
      SELECT Id
      FROM User
      WHERE LastName = 'Refund Test Processor'
      WITH SYSTEM_MODE
      LIMIT 1
    ];
  }
  public static List<Return_Request__c> requests(
    Integer count,
    String status,
    Boolean inspected
  ) {
    Store__c store = new Store__c(
      Name = 'Refund test store',
      Store_Code__c = 'RF-TEST',
      Region__c = 'Nam'
    );
    insert as system store;
    Account customer = new Account(Name = 'Refund test customer');
    insert as system customer;
    Order orderRecord = new Order(
      AccountId = customer.Id,
      EffectiveDate = Date.today(),
      Status = 'Draft',
      Store__c = store.Id
    );
    insert as system orderRecord;
    List<Return_Request__c> rows = new List<Return_Request__c>();
    for (Integer i = 0; i < count; i++) {
      rows.add(
        new Return_Request__c(
          Order__c = orderRecord.Id,
          Customer__c = customer.Id,
          Store__c = store.Id,
          Status__c = status,
          Actual_Refund_Amount__c = 1992000,
          Estimated_Refund_Amount__c = 2490000,
          Inspection_Completed_At__c = inspected ? System.now() : null
        )
      );
    }
    insert as system rows;
    if (inspected) {
      List<Return_Request_Line__c> lines = new List<Return_Request_Line__c>();
      for (Return_Request__c row : rows) {
        lines.add(
          new Return_Request_Line__c(
            Return_Request__c = row.Id,
            Inspection_Result__c = 'PASSED',
            Requested_Quantity__c = 1
          )
        );
      }
      insert as system lines;
    }
    return rows;
  }
  public static Refund_Transaction__c refund(Id requestId, String status) {
    Return_Request__c request = [
      SELECT Id, Name, Order__r.OrderNumber
      FROM Return_Request__c
      WHERE Id = :requestId
    ];
    Refund_Transaction__c refund = new Refund_Transaction__c(
      Return_Request__c = requestId,
      Merchant_Reference__c = request.Name,
      Idempotency_Key__c = request.Name,
      Order_Number__c = request.Order__r.OrderNumber,
      Refund_Amount__c = 1992000,
      Status__c = status,
      Attempt_Count__c = 0
    );
    insert as system refund;
    return refund;
  }

  public class Mock implements HttpCalloutMock {
    public String scenario;
    public Mock(String scenario) {
      this.scenario = scenario;
    }
    public HttpResponse respond(HttpRequest request) {
      Map<String, Object> payload = (Map<String, Object>) JSON.deserializeUntyped(
        request.getBody()
      );
      Assert.areEqual(
        payload.get('merchantRef'),
        request.getHeader('Idempotency-Key'),
        'BRD uses stable request number for the key.'
      );
      Assert.areEqual(
        Decimal.valueOf('1992000'),
        payload.get('amount'),
        'Never send the initial estimate.'
      );
      if (scenario == 'TIMEOUT') {
        throw new CalloutException('Read timed out');
      }
      HttpResponse response = new HttpResponse();
      if (scenario == 'HTTP_500' || scenario == 'HTTP_503') {
        response.setStatusCode(scenario == 'HTTP_500' ? 500 : 503);
        response.setBody('{}');
      } else if (scenario == 'INVALID_AMOUNT') {
        response.setStatusCode(422);
        response.setBody('{"errorCode":"INVALID_AMOUNT"}');
      } else {
        response.setStatusCode(200);
        response.setBody(
          JSON.serialize(
            new Map<String, Object>{
              'refundId' => 'PH-RF-88231',
              'status' => scenario
            }
          )
        );
      }
      return response;
    }
  }
  public static RefundDomain.Callback callback(
    Refund_Transaction__c row,
    String status
  ) {
    RefundDomain.Callback result = new RefundDomain.Callback();
    result.refundId = 'PH-RF-88231';
    result.merchantRef = row.Merchant_Reference__c;
    result.status = status;
    result.processedAt = System.now();
    if (status == 'FAILED') {
      result.failureReason = 'CARD_CLOSED';
    }
    return result;
  }
}
