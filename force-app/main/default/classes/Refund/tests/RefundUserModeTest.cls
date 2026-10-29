@IsTest
private class RefundUserModeTest {
  @TestSetup
  static void setup() {
    RefundTestDataFactory.setupUserModeRefunds();
  }

  @IsTest
  static void processorCanPublishRefundNotification() {
    Id requestId = [SELECT Id FROM Return_Request__c LIMIT 1].Id;
    System.runAs(RefundTestDataFactory.processor()) {
      Assert.isTrue(
        Schema.SObjectType.Refund_Notification__e.isCreateable(),
        'The worker fixture must have permission to publish refund notifications.'
      );
      Test.startTest();
      Database.SaveResult published = EventBus.publish(
        new Refund_Notification__e(
          Request_Id__c = requestId,
          Outcome__c = SmartReturnConstants.STATUS_COMPLETED
        )
      );
      Test.stopTest();
      Assert.isTrue(
        published.isSuccess(),
        'Publish the internal outcome: ' + JSON.serialize(published.getErrors())
      );
    }
  }

  @IsTest
  static void processorCompletesRequestOwnedByAnotherUser() {
    Return_Request__c request = [
      SELECT Id, OwnerId
      FROM Return_Request__c
      LIMIT 1
    ];
    User actor = RefundTestDataFactory.processor();
    Assert.areNotEqual(
      actor.Id,
      request.OwnerId,
      'Exercise explicitly shared work.'
    );
    Assert.areEqual(
      'Minimum Access - Salesforce',
      [SELECT Profile.Name FROM User WHERE Id = :actor.Id].Profile.Name,
      'The worker must not rely on an administrator profile.'
    );
    System.runAs(actor) {
      Test.setMock(
        HttpCalloutMock.class,
        new RefundTestDataFactory.Mock('SUCCESS')
      );
      Test.startTest();
      Id refundId = RefundService.startRefund(request.Id);
      Test.stopTest();
      Assert.areEqual(
        'SUCCEEDED',
        RefundSelector.byIds(new Set<Id>{ refundId }, false)[0].Status__c,
        'The worker can persist a successful response in user mode.'
      );
      Assert.areEqual(
        SmartReturnConstants.STATUS_COMPLETED,
        ReturnRequestSelector.byIds(new Set<Id>{ request.Id }, false)
          .get(request.Id)
          .Status__c,
        'The worker completes an explicitly shared request.'
      );
    }
  }

  @IsTest
  static void providerFailureCreatesAccountingTaskInUserMode() {
    Id requestId = [SELECT Id FROM Return_Request__c LIMIT 1].Id;
    System.runAs(RefundTestDataFactory.processor()) {
      Test.setMock(
        HttpCalloutMock.class,
        new RefundTestDataFactory.Mock('INVALID_AMOUNT')
      );
      Test.startTest();
      Id refundId = RefundService.startRefund(requestId);
      Test.stopTest();
      Refund_Transaction__c refund = RefundSelector.byIds(
        new Set<Id>{ refundId },
        false
      )[0];
      Assert.areEqual(
        'FAILED',
        refund.Status__c,
        'Persist the terminal provider failure.'
      );
      Assert.isNotNull(
        refund.Accounting_Task_Id__c,
        'Create accounting work without system-mode Task DML.'
      );
      Task work = [
        SELECT OwnerId, WhatId
        FROM Task
        WHERE Id = :refund.Accounting_Task_Id__c
      ];
      Assert.areEqual(refund.Id, work.WhatId, 'Link the work to this refund.');
      Assert.areEqual(
        RefundSelector.accountingQueue(),
        work.OwnerId,
        'Assign the accounting queue.'
      );
    }
  }

  @IsTest
  static void callbackCompletesExplicitlySharedRefund() {
    Return_Request__c request = [SELECT Id FROM Return_Request__c LIMIT 1];
    request.Status__c = SmartReturnConstants.STATUS_REFUND_PROCESSING;
    update as system request;
    Refund_Transaction__c refund = RefundTestDataFactory.refund(
      request.Id,
      'PENDING'
    );
    User actor = RefundTestDataFactory.processor();
    insert as system new Refund_Transaction__Share(
      ParentId = refund.Id,
      UserOrGroupId = actor.Id,
      AccessLevel = 'Edit'
    );
    System.runAs(actor) {
      Test.startTest();
      Integer status = RefundService.handleCallback(
        RefundTestDataFactory.callback(refund, 'SUCCESS')
      );
      Test.stopTest();
      Assert.areEqual(
        200,
        status,
        'Acknowledge a durable user-mode callback update.'
      );
      Assert.areEqual(
        'SUCCEEDED',
        RefundSelector.byIds(new Set<Id>{ refund.Id }, false)[0].Status__c,
        'Callback updates a refund shared with edit access.'
      );
    }
  }

  @IsTest
  static void readAccessAloneCannotUpdateAnotherOwnersRefund() {
    Return_Request__c request = [SELECT Id FROM Return_Request__c LIMIT 1];
    request.Status__c = SmartReturnConstants.STATUS_REFUND_PROCESSING;
    update as system request;
    Refund_Transaction__c refund = RefundTestDataFactory.refund(
      request.Id,
      'QUEUED'
    );
    System.runAs(RefundTestDataFactory.processor()) {
      Test.startTest();
      try {
        RefundService.claimRefunds(new Set<Id>{ refund.Id });
        Assert.fail(
          'View All plus object Edit must not bypass record edit access.'
        );
      } catch (DmlException e) {
        Assert.areEqual(
          'INSUFFICIENT_ACCESS_ON_CROSS_REFERENCE_ENTITY',
          e.getDmlStatusCode(0),
          'Enforce record edit access during the claim.'
        );
      }
      Test.stopTest();
      Refund_Transaction__c unchanged = RefundSelector.byIds(
        new Set<Id>{ refund.Id },
        false
      )[0];
      Assert.areEqual(
        'QUEUED',
        unchanged.Status__c,
        'Roll back the denied claim.'
      );
      Assert.areEqual(
        0,
        unchanged.Attempt_Count__c,
        'Do not consume an attempt without edit access.'
      );
      Assert.isNull(
        unchanged.Worker_Job_Id__c,
        'Do not retain a worker for a denied claim.'
      );
    }
  }
}
