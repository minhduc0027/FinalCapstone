@IsTest
private class RefundProcessingTest {
  @TestSetup
  static void setup() {
    User actor = RefundTestDataFactory.grantProcessor();
    System.runAs(actor) {
      RefundTestDataFactory.requests(1, 'INSPECTING', true);
    }
  }
  private static Id requestId() {
    return [SELECT Id FROM Return_Request__c LIMIT 1].Id;
  }
  @IsTest
  static void successfulRefund() {
    System.runAs(RefundTestDataFactory.processor()) {
      Test.setMock(
        HttpCalloutMock.class,
        new RefundTestDataFactory.Mock('SUCCESS')
      );
      Test.startTest();
      Id idValue = RefundService.startRefund(requestId());
      Test.stopTest();
      Refund_Transaction__c row = RefundSelector.byIds(
        new Set<Id>{ idValue },
        false
      )[0];
      Assert.areEqual(
        'SUCCEEDED',
        row.Status__c,
        'Successful provider payment is final.'
      );
      Assert.areEqual(
        1992000,
        row.Refund_Amount__c,
        'Use actual amount instead of estimate.'
      );
      Assert.areEqual(
        'PH-RF-88231',
        row.PayHub_Refund_Id__c,
        'Retain provider reference.'
      );
      Assert.isNotNull(row.Completed_At__c, 'Record completion timestamp.');
      Assert.areEqual(
        'COMPLETED',
        ReturnRequestSelector.byIds(new Set<Id>{ requestId() }, false)
          .get(requestId())
          .Status__c,
        'Complete canonical request.'
      );
      Integration_Log__c log = [
        SELECT Http_Status__c, Attempt_Number__c, Result__c, Request_Body__c
        FROM Integration_Log__c
        LIMIT 1
      ];
      Assert.areEqual(200, log.Http_Status__c, 'Audit HTTP result.');
      Assert.areEqual(1, log.Attempt_Number__c, 'Audit first attempt.');
      Assert.areEqual('SUCCESS', log.Result__c, 'Audit success.');
      Assert.isFalse(
        log.Request_Body__c.contains('Authorization'),
        'No credentials in audit.'
      );
    }
  }
  @IsTest
  static void pendingRefund() {
    System.runAs(RefundTestDataFactory.processor()) {
      Test.setMock(
        HttpCalloutMock.class,
        new RefundTestDataFactory.Mock('PENDING')
      );
      Test.startTest();
      Id idValue = RefundService.startRefund(requestId());
      Test.stopTest();
      Assert.areEqual(
        'PENDING',
        RefundSelector.byIds(new Set<Id>{ idValue }, false)[0].Status__c,
        'Wait for callback.'
      );
      Assert.areEqual(
        'REFUND_PROCESSING',
        ReturnRequestSelector.byIds(new Set<Id>{ requestId() }, false)
          .get(requestId())
          .Status__c,
        'Pending does not complete request.'
      );
    }
  }
  @IsTest
  static void invalidAmountNoRetry() {
    System.runAs(RefundTestDataFactory.processor()) {
      Test.setMock(
        HttpCalloutMock.class,
        new RefundTestDataFactory.Mock('INVALID_AMOUNT')
      );
      Test.startTest();
      Id idValue = RefundService.startRefund(requestId());
      Test.stopTest();
      Refund_Transaction__c row = RefundSelector.byIds(
        new Set<Id>{ idValue },
        false
      )[0];
      Assert.areEqual('FAILED', row.Status__c, '422 fails without retry.');
      Assert.isNull(row.Next_Retry_At__c, 'Do not retry data validation.');
      Assert.isNotNull(
        row.Accounting_Task_Id__c,
        'Accounting must receive work.'
      );
      Assert.areEqual(
        1,
        [SELECT COUNT() FROM Task WHERE WhatId = :idValue],
        'One accounting task.'
      );
    }
  }
  @IsTest
  static void duplicateInitiation() {
    System.runAs(RefundTestDataFactory.processor()) {
      Test.setMock(
        HttpCalloutMock.class,
        new RefundTestDataFactory.Mock('SUCCESS')
      );
      Id parent = requestId();
      Test.startTest();
      Id first = RefundService.startRefund(parent);
      Id second = RefundService.startRefund(parent);
      Test.stopTest();
      Assert.areEqual(first, second, 'Same request must return same refund.');
      Assert.areEqual(
        1,
        [SELECT COUNT() FROM Refund_Transaction__c],
        'No duplicate logical refund.'
      );
      Assert.areEqual(
        1,
        [SELECT COUNT() FROM Integration_Log__c],
        'Duplicate initiation must not send twice.'
      );
    }
  }
  @IsTest
  static void noSendBeforeInspection() {
    System.runAs(RefundTestDataFactory.processor()) {
      Return_Request__c request = new Return_Request__c(
        Id = requestId(),
        Inspection_Completed_At__c = null
      );
      update as system request;
      Test.startTest();
      try {
        RefundService.startRefund(request.Id);
        Assert.fail('Inspection must be finalized.');
      } catch (RefundDomain.RuleException e) {
        Assert.isTrue(
          e.getMessage().contains('Inspection not completed'),
          'Explain missing gate.'
        );
      }
      Test.stopTest();
      Assert.areEqual(
        0,
        [SELECT COUNT() FROM Refund_Transaction__c],
        'No transaction before inspection.'
      );
    }
  }

  @IsTest
  static void cannotInsertAnotherIdentityForSameRequest() {
    System.runAs(RefundTestDataFactory.processor()) {
      Id parent = requestId();
      Refund_Transaction__c first = RefundTestDataFactory.refund(
        parent,
        'QUEUED'
      );
      Refund_Transaction__c duplicate = first.clone(false, false, false, false);
      duplicate.Merchant_Reference__c = 'OTHER-REFERENCE';
      duplicate.Idempotency_Key__c = 'OTHER-KEY';
      Test.startTest();
      try {
        insert as system duplicate;
        Assert.fail('Direct inserts must not bypass canonical identity.');
      } catch (DmlException e) {
        Assert.areEqual(
          'FIELD_CUSTOM_VALIDATION_EXCEPTION',
          e.getDmlStatusCode(0),
          'Enforce canonical identity in metadata.'
        );
      }
      Test.stopTest();
      Assert.areEqual(
        1,
        [SELECT COUNT() FROM Refund_Transaction__c],
        'Exactly one logical refund remains.'
      );
    }
  }
  @IsTest
  static void cannotChangePersistedAmount() {
    System.runAs(RefundTestDataFactory.processor()) {
      Refund_Transaction__c refund = RefundTestDataFactory.refund(
        requestId(),
        'QUEUED'
      );
      refund.Refund_Amount__c = 1;
      Test.startTest();
      try {
        update as system refund;
        Assert.fail('Changing payment payload would break idempotent retries.');
      } catch (DmlException e) {
        Assert.areEqual(
          'FIELD_CUSTOM_VALIDATION_EXCEPTION',
          e.getDmlStatusCode(0),
          'Freeze the persisted amount.'
        );
      }
      Test.stopTest();
    }
  }
}
