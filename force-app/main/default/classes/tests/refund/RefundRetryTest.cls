@IsTest
private class RefundRetryTest {
  @TestSetup
  static void setup() {
    User actor = RefundTestDataFactory.grantProcessor();
    System.runAs(actor) {
      RefundTestDataFactory.requests(1, 'REFUND_PROCESSING', true);
    }
  }
  private static Refund_Transaction__c priorAttempt(
    Integer count,
    Integer minutes
  ) {
    Refund_Transaction__c row = RefundTestDataFactory.refund(
      [SELECT Id FROM Return_Request__c LIMIT 1].Id,
      'QUEUED'
    );
    row.Attempt_Count__c = count;
    row.Last_Attempt_At__c = System.now().addMinutes(-minutes);
    row.Next_Retry_At__c = row.Last_Attempt_At__c.addMinutes(15);
    row.Last_Error_Code__c = 'OUTCOME_UNCERTAIN';
    update as system row;
    return row;
  }
  @IsTest
  static void http500SchedulesRetry() {
    System.runAs(RefundTestDataFactory.processor()) {
      Refund_Transaction__c row = priorAttempt(0, 16);
      Test.setMock(
        HttpCalloutMock.class,
        new RefundTestDataFactory.Mock('HTTP_500')
      );
      Test.startTest();
      RefundService.claimRefunds(new Set<Id>{ row.Id });
      Test.stopTest();
      row = RefundSelector.byIds(new Set<Id>{ row.Id }, false)[0];
      Assert.areEqual(
        'QUEUED',
        row.Status__c,
        'System failure schedules retry.'
      );
      Assert.areEqual(
        row.Last_Attempt_At__c.addMinutes(15),
        row.Next_Retry_At__c,
        'Enforce 15-minute interval.'
      );
    }
  }
  @IsTest
  static void http503SchedulesRetry() {
    System.runAs(RefundTestDataFactory.processor()) {
      Refund_Transaction__c row = priorAttempt(0, 16);
      Test.setMock(
        HttpCalloutMock.class,
        new RefundTestDataFactory.Mock('HTTP_503')
      );
      Test.startTest();
      RefundService.claimRefunds(new Set<Id>{ row.Id });
      Test.stopTest();
      Assert.areEqual(
        'QUEUED',
        RefundSelector.byIds(new Set<Id>{ row.Id }, false)[0].Status__c,
        '503 is retryable.'
      );
    }
  }
  @IsTest
  static void timeoutIsLogged() {
    System.runAs(RefundTestDataFactory.processor()) {
      Refund_Transaction__c row = priorAttempt(0, 16);
      Test.setMock(
        HttpCalloutMock.class,
        new RefundTestDataFactory.Mock('TIMEOUT')
      );
      Test.startTest();
      RefundService.claimRefunds(new Set<Id>{ row.Id });
      Test.stopTest();
      row = RefundSelector.byIds(new Set<Id>{ row.Id }, false)[0];
      Assert.areEqual(
        'QUEUED',
        row.Status__c,
        'Timeout does not prove failure to pay.'
      );
      Integration_Log__c log = [
        SELECT Result__c, Http_Status__c
        FROM Integration_Log__c
        LIMIT 1
      ];
      Assert.areEqual(
        'TIMEOUT',
        log.Result__c,
        'Keep uncertain exchange evidence.'
      );
      Assert.isNull(log.Http_Status__c, 'No invented timeout status.');
    }
  }
  @IsTest
  static void exhaustedRetryCreatesOneTask() {
    System.runAs(RefundTestDataFactory.processor()) {
      Refund_Transaction__c row = priorAttempt(2, 16);
      Test.setMock(
        HttpCalloutMock.class,
        new RefundTestDataFactory.Mock('HTTP_503')
      );
      Test.startTest();
      RefundService.claimRefunds(new Set<Id>{ row.Id });
      Test.stopTest();
      row = RefundSelector.byIds(new Set<Id>{ row.Id }, false)[0];
      Assert.areEqual(3, row.Attempt_Count__c, 'Default is three total sends.');
      Assert.areEqual('FAILED', row.Status__c, 'Exhausted refund fails.');
      Assert.isNotNull(
        row.Accounting_Task_Id__c,
        'Accounting gets terminal failure.'
      );
      RefundService.claimRefunds(new Set<Id>{ row.Id });
      Assert.areEqual(
        1,
        [SELECT COUNT() FROM Task WHERE WhatId = :row.Id],
        'Never duplicate accounting work.'
      );
    }
  }
  @IsTest
  static void successThenTimeoutRetryUsesSameKey() {
    System.runAs(RefundTestDataFactory.processor()) {
      Refund_Transaction__c row = priorAttempt(1, 16);
      String key = row.Idempotency_Key__c;
      insert as system new Integration_Log__c(
        Refund_Transaction__c = row.Id,
        System__c = 'PAYHUB',
        Direction__c = 'OUTBOUND',
        Attempt_Number__c = 1,
        Result__c = 'TIMEOUT',
        Occurred_At__c = row.Last_Attempt_At__c,
        Error_Code__c = 'OUTCOME_UNCERTAIN'
      );
      // PayHub returns its cached first success for the same key; no new payment.
      Test.setMock(
        HttpCalloutMock.class,
        new RefundTestDataFactory.Mock('SUCCESS')
      );
      Test.startTest();
      RefundService.claimRefunds(new Set<Id>{ row.Id });
      Test.stopTest();
      row = RefundSelector.byIds(new Set<Id>{ row.Id }, false)[0];
      Assert.areEqual(
        key,
        row.Idempotency_Key__c,
        'OI-06 preserves original key.'
      );
      Assert.areEqual(
        'SUCCEEDED',
        row.Status__c,
        'Cached provider success reconciles timeout.'
      );
      Assert.areEqual(
        2,
        row.Attempt_Count__c,
        'Retry is another send, not another transaction.'
      );
      Assert.areEqual(
        2,
        [SELECT COUNT() FROM Integration_Log__c],
        'Audit both attempts.'
      );
    }
  }
  @IsTest
  static void tooEarlyRetryDoesNotDispatch() {
    System.runAs(RefundTestDataFactory.processor()) {
      Refund_Transaction__c row = priorAttempt(1, 14);
      Test.startTest();
      RefundService.claimRefunds(new Set<Id>{ row.Id });
      Test.stopTest();
      Assert.areEqual(
        1,
        RefundSelector.byIds(new Set<Id>{ row.Id }, false)[0].Attempt_Count__c,
        'No claim before due time.'
      );
      Assert.areEqual(
        0,
        [SELECT COUNT() FROM Integration_Log__c],
        'No fabricated exchange.'
      );
    }
  }

  @IsTest
  static void invalidTimeoutDoesNotClaimRefund() {
    System.runAs(RefundTestDataFactory.processor()) {
      Refund_Transaction__c row = priorAttempt(0, 16);
      PayHubClient.timeoutSecondsOverride = 0;

      Test.startTest();
      try {
        RefundService.claimRefunds(new Set<Id>{ row.Id });
        Assert.fail('Invalid timeout must stop the claim.');
      } catch (PayHubClient.ConfigurationException e) {
        Assert.isTrue(
          e.getMessage().contains('between 1 and 120'),
          'Explain the setting.'
        );
      }
      Test.stopTest();

      row = RefundSelector.byIds(new Set<Id>{ row.Id }, false)[0];
      Assert.areEqual(
        'QUEUED',
        row.Status__c,
        'Leave the refund ready after correction.'
      );
      Assert.areEqual(
        0,
        row.Attempt_Count__c,
        'Do not count a payment attempt.'
      );
      Assert.areEqual(
        0,
        [SELECT COUNT() FROM Integration_Log__c],
        'No PayHub exchange occurred.'
      );
    }
  }

  @IsTest
  static void invalidTimeoutDoesNotBlockCompletedRefund() {
    System.runAs(RefundTestDataFactory.processor()) {
      Refund_Transaction__c row = priorAttempt(1, 16);
      row.Status__c = 'SUCCEEDED';
      update as system row;
      PayHubClient.timeoutSecondsOverride = 0;

      Test.startTest();
      RefundService.claimRefunds(new Set<Id>{ row.Id });
      Test.stopTest();

      row = RefundSelector.byIds(new Set<Id>{ row.Id }, false)[0];
      Assert.areEqual('SUCCEEDED', row.Status__c, 'Keep the completed result.');
      Assert.areEqual(1, row.Attempt_Count__c, 'Do not change prior sends.');
    }
  }

  @IsTest
  static void invalidTimeoutAfterClaimReleasesRefund() {
    System.runAs(RefundTestDataFactory.processor()) {
      Refund_Transaction__c row = priorAttempt(1, 16);
      row.Status__c = 'PROCESSING';
      row.Worker_Job_Id__c = '707000000000001AAA';
      update as system row;
      PayHubClient.timeoutSecondsOverride = 0;

      Test.startTest();
      RefundService.processClaimed(row.Id, row.Worker_Job_Id__c);
      Test.stopTest();

      row = RefundSelector.byIds(new Set<Id>{ row.Id }, false)[0];
      Assert.areEqual('QUEUED', row.Status__c, 'Release the unsent claim.');
      Assert.areEqual(
        0,
        row.Attempt_Count__c,
        'Do not count an unsent payment.'
      );
      Assert.isNull(row.Worker_Job_Id__c, 'Clear the worker claim.');
      Assert.isNotNull(
        row.Next_Retry_At__c,
        'Retry only after the setting is corrected.'
      );
      Assert.areEqual(
        0,
        [SELECT COUNT() FROM Integration_Log__c],
        'No PayHub exchange occurred.'
      );
    }
  }
  @IsTest
  static void staleWorkerDoesNotSend() {
    System.runAs(RefundTestDataFactory.processor()) {
      Refund_Transaction__c row = priorAttempt(1, 16);
      row.Status__c = 'PROCESSING';
      row.Worker_Job_Id__c = '707000000000001';
      update as system row;
      Test.startTest();
      RefundService.processClaimed(row.Id, '707000000000002');
      Test.stopTest();
      Assert.areEqual(
        0,
        Limits.getCallouts(),
        'Stale worker performs no HTTP.'
      );
      Assert.areEqual(
        0,
        [SELECT COUNT() FROM Integration_Log__c],
        'No fake send audit.'
      );
    }
  }
  @IsTest
  static void schedulerDispatchesDueWork() {
    System.runAs(RefundTestDataFactory.processor()) {
      Refund_Transaction__c row = priorAttempt(1, 16);
      Test.setMock(
        HttpCalloutMock.class,
        new RefundTestDataFactory.Mock('SUCCESS')
      );
      Test.startTest();
      new RefundRetryScheduler().execute(null);
      Test.stopTest();
      Assert.areEqual(
        'SUCCEEDED',
        RefundSelector.byIds(new Set<Id>{ row.Id }, false)[0].Status__c,
        'Scheduler delegates due work.'
      );
    }
  }

  @IsTest
  static void threeConsecutiveFailuresKeepThreeAudits() {
    System.runAs(RefundTestDataFactory.processor()) {
      Refund_Transaction__c row = priorAttempt(0, 16);
      String key = row.Idempotency_Key__c;
      Test.startTest();
      for (Integer attempt = 1; attempt <= 3; attempt++) {
        row = RefundSelector.byIds(new Set<Id>{ row.Id }, false)[0];
        row.Status__c = 'PROCESSING';
        row.Attempt_Count__c = attempt;
        row.Worker_Job_Id__c = '707000000000001AAA';
        update as system row;
        PayHubClient.Result response = new PayHubClient.Result();
        response.httpStatus = 503;
        response.occurredAt = System.now().addMinutes((attempt - 1) * 15);
        response.durationMs = 1;
        response.responseBody = '{}';
        response.requestBody = JSON.serialize(
          new Map<String, Object>{ 'merchantRef' => row.Merchant_Reference__c }
        );
        RefundService.persistResponse(
          row,
          row.Worker_Job_Id__c,
          attempt,
          response
        );
      }
      Test.stopTest();
      row = RefundSelector.byIds(new Set<Id>{ row.Id }, false)[0];
      Assert.areEqual(
        'FAILED',
        row.Status__c,
        'UAT-06 stops after third failure.'
      );
      Assert.areEqual(
        key,
        row.Idempotency_Key__c,
        'Every send retains the same key.'
      );
      Assert.areEqual(
        3,
        [
          SELECT COUNT()
          FROM Integration_Log__c
          WHERE Refund_Transaction__c = :row.Id
        ],
        'Retain all three exchanges.'
      );
      Assert.areEqual(
        1,
        [SELECT COUNT() FROM Task WHERE WhatId = :row.Id],
        'One Accounting action after exhaustion.'
      );
    }
  }
  @IsTest
  static void supersededWorkerResultIsAuditedWithoutApplying() {
    System.runAs(RefundTestDataFactory.processor()) {
      Refund_Transaction__c row = priorAttempt(1, 16);
      row.Status__c = 'PROCESSING';
      row.Worker_Job_Id__c = '707000000000002AAA';
      update as system row;
      PayHubClient.Result response = new PayHubClient.Result();
      response.httpStatus = 503;
      response.occurredAt = System.now();
      response.durationMs = 1;
      Test.startTest();
      RefundService.persistResponse(row, '707000000000001AAA', 1, response);
      Test.stopTest();
      Assert.areEqual(
        'PROCESSING',
        RefundSelector.byIds(new Set<Id>{ row.Id }, false)[0].Status__c,
        'Stale response cannot override newer claim.'
      );
      Assert.areEqual(
        1,
        [
          SELECT COUNT()
          FROM Integration_Log__c
          WHERE Error_Code__c = 'STALE_WORKER'
        ],
        'Keep actual stale exchange evidence.'
      );
    }
  }
}
