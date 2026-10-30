@IsTest
private class RefundDomainTest {
  @TestSetup
  static void setup() {
    User actor = RefundTestDataFactory.grantProcessor();
    System.runAs(actor) {
      RefundTestDataFactory.requests(251, 'INSPECTING', true);
    }
  }
  private static Refund_Transaction__c queued() {
    return new Refund_Transaction__c(
      Status__c = 'QUEUED',
      Attempt_Count__c = 1,
      Last_Attempt_At__c = System.now().addSeconds(-5),
      Next_Retry_At__c = System.now().addSeconds(-1)
    );
  }
  @IsTest
  static void eligibleInspection() {
    System.runAs(RefundTestDataFactory.processor()) {
      Return_Request__c request = [
        SELECT
          Id,
          Status__c,
          Inspection_Completed_At__c,
          Actual_Refund_Amount__c,
          Order__c
        FROM Return_Request__c
        LIMIT 1
      ];
      Test.startTest();
      RefundDomain.validateInspection(
        request,
        ReturnRequestSelector.lines(new Set<Id>{ request.Id })
      );
      Test.stopTest();
      Assert.areEqual(
        1992000,
        request.Actual_Refund_Amount__c,
        'Use actual post-inspection amount.'
      );
    }
  }
  @IsTest
  static void noInspectionMarker() {
    System.runAs(RefundTestDataFactory.processor()) {
      Return_Request__c request = new Return_Request__c(
        Status__c = 'INSPECTING'
      );
      Test.startTest();
      try {
        RefundDomain.validateInspection(
          request,
          new List<Return_Request_Line__c>()
        );
        Assert.fail('Must reject unfinished inspection.');
      } catch (RefundDomain.RuleException e) {
        Assert.isTrue(
          e.getMessage().contains('Inspection not completed'),
          'Explain the gate.'
        );
      }
      Test.stopTest();
    }
  }
  @IsTest
  static void uninspectedLine() {
    System.runAs(RefundTestDataFactory.processor()) {
      Return_Request__c request = [
        SELECT
          Id,
          Status__c,
          Inspection_Completed_At__c,
          Actual_Refund_Amount__c,
          Order__c
        FROM Return_Request__c
        LIMIT 1
      ];
      Test.startTest();
      try {
        RefundDomain.validateInspection(
          request,
          new List<Return_Request_Line__c>{
            new Return_Request_Line__c(Inspection_Result__c = 'NOT_INSPECTED')
          }
        );
        Assert.fail('Unfinished lines must block.');
      } catch (RefundDomain.RuleException e) {
        Assert.isTrue(
          e.getMessage().contains('Invalid inspection result'),
          'Identify missing results.'
        );
      }
      Test.stopTest();
    }
  }
  @IsTest
  static void noPassedLine() {
    System.runAs(RefundTestDataFactory.processor()) {
      Return_Request__c request = [
        SELECT
          Id,
          Status__c,
          Inspection_Completed_At__c,
          Actual_Refund_Amount__c,
          Order__c
        FROM Return_Request__c
        LIMIT 1
      ];
      Test.startTest();
      try {
        RefundDomain.validateInspection(
          request,
          new List<Return_Request_Line__c>{
            new Return_Request_Line__c(Inspection_Result__c = 'FAILED')
          }
        );
        Assert.fail('No refund if every item failed.');
      } catch (RefundDomain.RuleException e) {
        Assert.isTrue(
          e.getMessage().contains('no passed lines'),
          'Explain passed-item rule.'
        );
      }
      Test.stopTest();
    }
  }
  @IsTest
  static void minimumInterval() {
    System.runAs(RefundTestDataFactory.processor()) {
      Refund_Transaction__c refund = queued();
      Datetime nowValue = System.now();
      refund.Last_Attempt_At__c = nowValue.addSeconds(-4);
      Test.startTest();
      Boolean allowed = RefundDomain.canClaim(
        refund,
        new RefundDomain.Policy(3, 5),
        nowValue
      );
      Test.stopTest();
      Assert.isFalse(allowed, 'Never retry earlier than 5 seconds.');
    }
  }
  @IsTest
  static void intervalBoundary() {
    System.runAs(RefundTestDataFactory.processor()) {
      Datetime nowValue = System.now();
      Refund_Transaction__c refund = queued();
      refund.Last_Attempt_At__c = nowValue.addSeconds(-5);
      Test.startTest();
      Boolean allowed = RefundDomain.canClaim(
        refund,
        new RefundDomain.Policy(5, 5),
        nowValue
      );
      Test.stopTest();
      Assert.isTrue(allowed, 'Allow due retry with Admin-configured maximum.');
    }
  }
  @IsTest
  static void pendingNotRetried() {
    System.runAs(RefundTestDataFactory.processor()) {
      Refund_Transaction__c refund = queued();
      refund.Status__c = 'PENDING';
      Test.startTest();
      Boolean allowed = RefundDomain.canClaim(
        refund,
        new RefundDomain.Policy(3, 5),
        System.now()
      );
      Test.stopTest();
      Assert.isFalse(allowed, 'Pending waits for callback, not a new send.');
    }
  }
  @IsTest
  static void staleWorker() {
    System.runAs(RefundTestDataFactory.processor()) {
      Refund_Transaction__c refund = queued();
      refund.Status__c = 'PROCESSING';
      refund.Worker_Job_Id__c = 'new-worker';
      Test.startTest();
      Boolean owns = RefundDomain.ownsClaim(refund, 'old-worker', 1);
      Test.stopTest();
      Assert.isFalse(owns, 'Superseded workers cannot persist outcomes.');
    }
  }
  @IsTest
  static void classifySuccess() {
    System.runAs(RefundTestDataFactory.processor()) {
      PayHubClient.Result response = new PayHubClient.Result();
      response.httpStatus = 200;
      response.status = 'SUCCESS';
      response.refundId = 'PH-1';
      Test.startTest();
      RefundDomain.Decision decision = RefundDomain.classify(response);
      Test.stopTest();
      Assert.areEqual(
        'SUCCEEDED',
        decision.status,
        'Provider success is final.'
      );
    }
  }
  @IsTest
  static void classifyPending() {
    System.runAs(RefundTestDataFactory.processor()) {
      PayHubClient.Result response = new PayHubClient.Result();
      response.httpStatus = 200;
      response.status = 'PENDING';
      response.refundId = 'PH-1';
      Test.startTest();
      RefundDomain.Decision decision = RefundDomain.classify(response);
      Test.stopTest();
      Assert.areEqual('PENDING', decision.status, 'Pending is not completed.');
    }
  }
  @IsTest
  static void classifyInvalidAmount() {
    System.runAs(RefundTestDataFactory.processor()) {
      PayHubClient.Result response = new PayHubClient.Result();
      response.httpStatus = 422;
      response.errorCode = 'INVALID_AMOUNT';
      Test.startTest();
      RefundDomain.Decision decision = RefundDomain.classify(response);
      Test.stopTest();
      Assert.isFalse(
        decision.retryable,
        'Validation failures are not retried.'
      );
    }
  }
  @IsTest
  static void classifyTimeout() {
    System.runAs(RefundTestDataFactory.processor()) {
      PayHubClient.Result response = new PayHubClient.Result();
      response.transportFailure = true;
      Test.startTest();
      RefundDomain.Decision decision = RefundDomain.classify(response);
      Test.stopTest();
      Assert.isTrue(
        decision.retryable,
        'Retry the same key for uncertain outcomes.'
      );
      Assert.areEqual('TIMEOUT', decision.logResult, 'Keep timeout evidence.');
    }
  }
  @IsTest
  static void rejectInvalidPolicy() {
    System.runAs(RefundTestDataFactory.processor()) {
      Test.startTest();
      try {
        new RefundDomain.Policy(3, 4);
        Assert.fail('Reject too-short intervals.');
      } catch (RefundDomain.RuleException e) {
        Assert.isTrue(e.getMessage().contains('5'), 'Explain minimum.');
      }
      Test.stopTest();
    }
  }
  @IsTest
  static void bulkSelector251() {
    System.runAs(RefundTestDataFactory.processor()) {
      Set<Id> ids = new Map<Id, Return_Request__c>(
          [SELECT Id FROM Return_Request__c]
        )
        .keySet();
      Test.startTest();
      Map<Id, Return_Request__c> requests = ReturnRequestSelector.byIds(
        ids,
        false
      );
      List<Return_Request_Line__c> lines = ReturnRequestSelector.lines(ids);
      Test.stopTest();
      Assert.areEqual(
        251,
        requests.size(),
        'Selector crosses the 200-record boundary.'
      );
      Assert.areEqual(
        251,
        lines.size(),
        'Load all inspection results in one query.'
      );
    }
  }

  @IsTest
  static void selectorWorkAndIdentityQueries() {
    System.runAs(RefundTestDataFactory.processor()) {
      Return_Request__c request = [SELECT Id FROM Return_Request__c LIMIT 1];
      Refund_Transaction__c refund = RefundTestDataFactory.refund(
        request.Id,
        'QUEUED'
      );
      Test.startTest();
      Assert.areEqual(
        1,
        RefundSelector.byIds(new Set<Id>{ refund.Id }, true).size(),
        'Lock selected refund.'
      );
      Assert.areEqual(
        1,
        RefundSelector.byMerchant(refund.Merchant_Reference__c, true).size(),
        'Find stable merchant identity.'
      );
      Assert.areEqual(
        1,
        RefundSelector.due(System.now(), 15, 10).size(),
        'Find due work.'
      );
      Assert.areEqual(
        10,
        ReturnRequestSelector.waitingForRefund(10).size(),
        'Bound inspection recovery.'
      );
      Assert.areEqual(
        0,
        RefundSelector.byIds(null, false).size(),
        'Null IDs are empty.'
      );
      Assert.areEqual(
        0,
        ReturnRequestSelector.byIds(new Set<Id>(), false).size(),
        'Empty requests are empty.'
      );
      Assert.isNotNull(
        RefundSelector.accountingQueue(),
        'Resolve dedicated Accounting queue.'
      );
      Test.stopTest();
    }
  }
  @IsTest
  static void callbackContract() {
    System.runAs(RefundTestDataFactory.processor()) {
      RefundDomain.Callback callback = new RefundDomain.Callback();
      callback.refundId = 'PH-1';
      callback.merchantRef = 'RR-1';
      callback.status = 'SUCCESS';
      callback.processedAt = System.now();
      Test.startTest();
      RefundDomain.validateCallback(callback);
      Test.stopTest();
      Assert.areEqual(
        'SUCCESS',
        callback.status,
        'Valid callback is accepted without mutation.'
      );
    }
  }
  @IsTest
  static void rejectInvalidCallback() {
    System.runAs(RefundTestDataFactory.processor()) {
      Test.startTest();
      try {
        RefundDomain.validateCallback(null);
        Assert.fail('Reject missing callback.');
      } catch (RefundDomain.RuleException e) {
        Assert.isTrue(
          e.getMessage().contains('Invalid callback data'),
          'Explain contract violation.'
        );
      }
      Test.stopTest();
    }
  }
  @IsTest
  static void expiredClaimRecovery() {
    System.runAs(RefundTestDataFactory.processor()) {
      Refund_Transaction__c refund = queued();
      refund.Status__c = 'PROCESSING';
      Datetime nowValue = System.now();
      refund.Last_Attempt_At__c = nowValue.addSeconds(-5);
      Test.startTest();
      Boolean eligible = RefundDomain.canClaim(
        refund,
        new RefundDomain.Policy(3, 5),
        nowValue
      );
      Test.stopTest();
      Assert.isTrue(
        eligible,
        'Recover abandoned claim only after lease interval.'
      );
    }
  }

  @IsTest
  static void confirmedProviderFailureIsNotRetried() {
    PayHubClient.Result response = new PayHubClient.Result();
    response.httpStatus = 200;
    response.status = 'FAILED';
    response.refundId = 'PH-RF-1';
    Test.startTest();
    RefundDomain.Decision decision = RefundDomain.classify(response);
    Test.stopTest();
    Assert.areEqual(
      'FAILED',
      decision.status,
      'Confirmed failure is terminal.'
    );
    Assert.isFalse(decision.retryable, 'Do not retry a provider rejection.');
  }
}
