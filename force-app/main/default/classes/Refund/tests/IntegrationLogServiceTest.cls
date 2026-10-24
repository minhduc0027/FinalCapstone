@IsTest
private class IntegrationLogServiceTest {
  @TestSetup
  static void setup() {
    User actor = RefundTestDataFactory.grantProcessor();
    RefundTestDataFactory.accountant();
    System.runAs(actor) {
      Return_Request__c request = RefundTestDataFactory.requests(
        1,
        'REFUND_PROCESSING',
        true
      )[0];
      RefundTestDataFactory.refund(request.Id, 'PENDING');
    }
  }

  private static Refund_Transaction__c refund() {
    return [
      SELECT Id, Attempt_Count__c, Merchant_Reference__c
      FROM Refund_Transaction__c
      WITH SYSTEM_MODE
      LIMIT 1
    ];
  }

  @IsTest
  static void recordsOutboundResponseFields() {
    System.runAs(RefundTestDataFactory.processor()) {
      Refund_Transaction__c row = refund();
      row.Attempt_Count__c = 2;
      PayHubClient.Result response = new PayHubClient.Result();
      response.requestBody = '{"amount":1992000}';
      response.responseBody = '{"status":"PENDING"}';
      response.httpStatus = 200;
      response.durationMs = Long.valueOf('12');
      response.occurredAt = System.now();

      Test.startTest();
      IntegrationLogService.recordOutbound(row, 'PENDING', null, response);
      Test.stopTest();

      Integration_Log__c entry = [
        SELECT
          Refund_Transaction__c,
          Direction__c,
          Endpoint__c,
          Attempt_Number__c,
          Request_Body__c,
          Response_Body__c,
          Http_Status__c,
          Duration_Ms__c,
          Result__c,
          Occurred_At__c
        FROM Integration_Log__c
        WITH SYSTEM_MODE
        LIMIT 1
      ];
      Assert.areEqual(row.Id, entry.Refund_Transaction__c, 'Link the refund.');
      Assert.areEqual('OUTBOUND', entry.Direction__c, 'Mark the direction.');
      Assert.areEqual(
        '/v1/refunds',
        entry.Endpoint__c,
        'Keep the audit endpoint.'
      );
      Assert.areEqual(2, entry.Attempt_Number__c, 'Keep the attempt.');
      Assert.areEqual(
        response.requestBody,
        entry.Request_Body__c,
        'Keep request data.'
      );
      Assert.areEqual(
        response.responseBody,
        entry.Response_Body__c,
        'Keep response data.'
      );
      Assert.areEqual(200, entry.Http_Status__c, 'Keep HTTP status.');
      Assert.areEqual(12, entry.Duration_Ms__c, 'Keep duration.');
      Assert.areEqual('PENDING', entry.Result__c, 'Keep result.');
      Assert.areEqual(
        response.occurredAt,
        entry.Occurred_At__c,
        'Keep provider time.'
      );
    }
  }

  @IsTest
  static void recordsExpiredClaimsInOneDml() {
    System.runAs(RefundTestDataFactory.processor()) {
      Refund_Transaction__c row = refund();
      row.Attempt_Count__c = 1;
      List<Integration_Log__c> entries = new List<Integration_Log__c>{
        IntegrationLogService.outboundEntry(
          row,
          'TIMEOUT',
          'ABANDONED_WORKER',
          null
        ),
        IntegrationLogService.outboundEntry(
          row,
          'TIMEOUT',
          'ABANDONED_WORKER',
          null
        )
      };

      Test.startTest();
      Integer beforeDml = Limits.getDmlStatements();
      IntegrationLogService.recordAll(entries);
      Integer usedDml = Limits.getDmlStatements() - beforeDml;
      Test.stopTest();

      Assert.areEqual(1, usedDml, 'Batch audit entries in one DML.');
      Assert.areEqual(
        2,
        [SELECT COUNT() FROM Integration_Log__c],
        'Keep both audit entries.'
      );
      Assert.areEqual(
        1,
        entries[0].Attempt_Number__c,
        'Keep the original attempt.'
      );
    }
  }

  @IsTest
  static void recordsUnknownCallbackWithoutRefund() {
    System.runAs(RefundTestDataFactory.processor()) {
      RefundDomain.Callback callback = RefundTestDataFactory.callback(
        refund(),
        'SUCCESS'
      );

      Test.startTest();
      IntegrationLogService.recordCallback(null, callback, 'UNKNOWN_MERCHANT');
      Test.stopTest();

      Integration_Log__c entry = [
        SELECT
          Refund_Transaction__c,
          Direction__c,
          Http_Status__c,
          Error_Code__c
        FROM Integration_Log__c
        WITH SYSTEM_MODE
        LIMIT 1
      ];
      Assert.isNull(
        entry.Refund_Transaction__c,
        'Unknown merchant has no refund.'
      );
      Assert.areEqual('INBOUND', entry.Direction__c, 'Mark the direction.');
      Assert.areEqual(
        404,
        entry.Http_Status__c,
        'Keep callback response status.'
      );
      Assert.areEqual(
        'UNKNOWN_MERCHANT',
        entry.Error_Code__c,
        'Keep audit reason.'
      );
    }
  }

  @IsTest
  static void accountantCannotRecordOutboundLog() {
    User accountant = [
      SELECT Id
      FROM User
      WHERE LastName = 'Refund Test Accountant'
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    System.runAs(accountant) {
      Test.startTest();
      try {
        IntegrationLogService.recordOutbound(refund(), 'FAILED', null, null);
        Assert.fail('Accounting cannot create a PayHub exchange.');
      } catch (IntegrationLogService.IntegrationLogException expected) {
        Assert.areEqual(
          0,
          [SELECT COUNT() FROM Integration_Log__c],
          'No audit record was inserted.'
        );
      }
      Test.stopTest();
    }
  }
}
