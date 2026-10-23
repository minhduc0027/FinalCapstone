@IsTest
private class RefundCallbackTest {
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
  private static Refund_Transaction__c row() {
    return RefundSelector.byIds(
      new Map<Id, Refund_Transaction__c>([SELECT Id FROM Refund_Transaction__c])
        .keySet(),
      false
    )[0];
  }
  @IsTest
  static void pendingToSuccessAndNotification() {
    System.runAs(RefundTestDataFactory.processor()) {
      Refund_Transaction__c refund = row();
      Test.startTest();
      Integer status = RefundService.handleCallback(
        RefundTestDataFactory.callback(refund, 'SUCCESS')
      );
      Test.stopTest();
      Assert.areEqual(200, status, 'Acknowledge durable success.');
      refund = row();
      Assert.areEqual(
        'SUCCEEDED',
        refund.Status__c,
        'Finalize pending refund.'
      );
      Assert.isNotNull(
        refund.Provider_Processed_At__c,
        'Preserve provider event time.'
      );
      Assert.areEqual(
        1,
        RefundService.eventsPublished,
        'Publish once through PublishAfterCommit event.'
      );
    }
  }
  @IsTest
  static void duplicateCallbackDoesNotMutateRefund() {
    System.runAs(RefundTestDataFactory.processor()) {
      RefundDomain.Callback callback = RefundTestDataFactory.callback(
        row(),
        'SUCCESS'
      );
      Test.startTest();
      RefundService.handleCallback(callback);
      Datetime completed = row().Completed_At__c;
      Integer status = RefundService.handleCallback(callback);
      Test.stopTest();
      Assert.areEqual(200, status, 'Duplicate is safely acknowledged.');
      Assert.areEqual(
        completed,
        row().Completed_At__c,
        'Do not update completed payment again.'
      );
      Assert.areEqual(
        1,
        RefundService.eventsPublished,
        'No duplicate notification.'
      );
      Assert.areEqual(
        2,
        [SELECT COUNT() FROM Integration_Log__c],
        'Preserve both receipts.'
      );
    }
  }
  @IsTest
  static void pendingToFailed() {
    System.runAs(RefundTestDataFactory.processor()) {
      Test.startTest();
      RefundService.handleCallback(
        RefundTestDataFactory.callback(row(), 'FAILED')
      );
      Test.stopTest();
      Assert.areEqual(
        'FAILED',
        row().Status__c,
        'Persist final provider failure.'
      );
      Assert.areEqual(
        'REFUND_FAILED',
        ReturnRequestSelector.byIds(
            new Set<Id>{ row().Return_Request__c },
            false
          )
          .get(row().Return_Request__c)
          .Status__c,
        'Fail canonical request.'
      );
      Assert.areEqual(1, [SELECT COUNT() FROM Task], 'Create accounting work.');
    }
  }
  @IsTest
  static void outOfOrderFailureCannotOverwriteSuccess() {
    System.runAs(RefundTestDataFactory.processor()) {
      RefundDomain.Callback success = RefundTestDataFactory.callback(
        row(),
        'SUCCESS'
      );
      RefundDomain.Callback failure = RefundTestDataFactory.callback(
        row(),
        'FAILED'
      );
      failure.processedAt = success.processedAt.addMinutes(-1);
      Test.startTest();
      RefundService.handleCallback(success);
      RefundService.handleCallback(failure);
      Test.stopTest();
      Assert.areEqual(
        'SUCCEEDED',
        row().Status__c,
        'Never reverse confirmed success.'
      );
      Assert.areEqual(
        1,
        RefundService.eventsPublished,
        'Do not publish stale failure.'
      );
    }
  }
  @IsTest
  static void lateSuccessAfterFailureRequiresAccounting() {
    System.runAs(RefundTestDataFactory.processor()) {
      Test.startTest();
      RefundService.handleCallback(
        RefundTestDataFactory.callback(row(), 'FAILED')
      );
      RefundService.handleCallback(
        RefundTestDataFactory.callback(row(), 'SUCCESS')
      );
      Test.stopTest();
      Assert.areEqual(
        'FAILED',
        row().Status__c,
        'Appendix C forbids automatic Failed-to-Completed.'
      );
      Assert.areEqual(
        1,
        [SELECT COUNT() FROM Task],
        'Use existing reconciliation work.'
      );
      Assert.areEqual(
        1,
        [
          SELECT COUNT()
          FROM Integration_Log__c
          WHERE Error_Code__c = 'RECONCILIATION_REQUIRED'
        ],
        'Preserve contradiction.'
      );
    }
  }
  @IsTest
  static void unknownMerchantReturns404() {
    System.runAs(RefundTestDataFactory.processor()) {
      RefundDomain.Callback callback = RefundTestDataFactory.callback(
        row(),
        'SUCCESS'
      );
      callback.merchantRef = 'RR-UNKNOWN';
      Test.startTest();
      Integer status = RefundService.handleCallback(callback);
      Test.stopTest();
      Assert.areEqual(404, status, 'BRD requires unknown merchant 404.');
      Assert.areEqual(
        1,
        [SELECT COUNT() FROM Integration_Log__c],
        'Keep unmatched callback evidence.'
      );
    }
  }
  @IsTest
  static void manualCompletionWithReference() {
    Id refundId;
    System.runAs(RefundTestDataFactory.processor()) {
      RefundService.handleCallback(
        RefundTestDataFactory.callback(row(), 'FAILED')
      );
      refundId = row().Id;
    }
    User accountant = [
      SELECT Id
      FROM User
      WHERE LastName = 'Refund Test Accountant'
    ];
    System.runAs(accountant) {
      Test.startTest();
      RefundService.manualComplete(refundId, 'MANUAL-001');
      RefundService.manualComplete(refundId, 'MANUAL-001');
      Test.stopTest();
      Refund_Transaction__c refund = RefundSelector.byIds(
        new Set<Id>{ refundId },
        false
      )[0];
      Assert.areEqual(
        'FAILED',
        refund.Status__c,
        'Preserve provider failure evidence.'
      );
      Assert.areEqual(
        'MANUAL-001',
        refund.Manual_Reference__c,
        'Record external payment reference.'
      );
      Assert.areEqual(
        accountant.Id,
        refund.Manual_Completed_By__c,
        'Record actor.'
      );
      Assert.areEqual(
        'COMPLETED',
        ReturnRequestSelector.byIds(
            new Set<Id>{ refund.Return_Request__c },
            false
          )
          .get(refund.Return_Request__c)
          .Status__c,
        'Accounting completes return.'
      );
      Assert.areEqual(
        2,
        RefundService.eventsPublished,
        'One failure event plus one manual completion event; no duplicate action.'
      );
      Assert.areEqual(
        0,
        Limits.getCallouts(),
        'Manual action never sends another payment.'
      );
    }
  }
  @IsTest
  static void unauthorizedManualCompletion() {
    System.runAs(RefundTestDataFactory.processor()) {
      Test.startTest();
      try {
        RefundService.manualComplete(row().Id, 'MANUAL-001');
        Assert.fail('Processor is not Accounting.');
      } catch (RefundService.RefundException e) {
        Assert.isTrue(
          e.getMessage().contains('do not have permission'),
          'Require dedicated permission.'
        );
      }
      Test.stopTest();
    }
  }
  @IsTest
  static void restParsesOffsetTimestamp() {
    System.runAs(RefundTestDataFactory.processor()) {
      RefundDomain.Callback callback = RefundTestDataFactory.callback(
        row(),
        'SUCCESS'
      );
      RestRequest request = new RestRequest();
      request.httpMethod = 'POST';
      request.requestBody = Blob.valueOf(
        JSON.serialize(
          new Map<String, Object>{
            'refundId' => callback.refundId,
            'merchantRef' => callback.merchantRef,
            'status' => 'SUCCESS',
            'processedAt' => '2026-10-05T10:02:10+07:00'
          }
        )
      );
      RestContext.request = request;
      RestContext.response = new RestResponse();
      Test.startTest();
      RefundCallbackRest.receive();
      Test.stopTest();
      Assert.areEqual(
        200,
        RestContext.response.statusCode,
        'Accept authenticated contract.'
      );
      Assert.areEqual(
        Datetime.newInstanceGmt(2026, 10, 5, 3, 2, 10),
        row().Provider_Processed_At__c,
        'Normalize provider offset accurately.'
      );
    }
  }
  @IsTest
  static void restRejectsMalformedInput() {
    System.runAs(RefundTestDataFactory.processor()) {
      RestRequest request = new RestRequest();
      request.requestBody = Blob.valueOf('{invalid');
      RestContext.request = request;
      RestContext.response = new RestResponse();
      Test.startTest();
      RefundCallbackRest.receive();
      Test.stopTest();
      Assert.areEqual(
        400,
        RestContext.response.statusCode,
        'Return controlled validation failure.'
      );
      Assert.areEqual(
        1,
        [
          SELECT COUNT()
          FROM Integration_Log__c
          WHERE Error_Code__c = 'INVALID_CALLBACK'
        ],
        'Audit malformed receipt without raw input.'
      );
    }
  }
  @IsTest
  static void restRequiresCustomPermission() {
    User accountant = [
      SELECT Id
      FROM User
      WHERE LastName = 'Refund Test Accountant'
    ];
    System.runAs(accountant) {
      RestContext.request = new RestRequest();
      RestContext.response = new RestResponse();
      Test.startTest();
      RefundCallbackRest.receive();
      Test.stopTest();
      Assert.areEqual(
        403,
        RestContext.response.statusCode,
        'Accounting is not a callback integration identity.'
      );
    }
  }
  @IsTest
  static void providerIdentityMismatchDoesNotNotify() {
    System.runAs(RefundTestDataFactory.processor()) {
      RefundDomain.Callback callback = RefundTestDataFactory.callback(
        row(),
        'SUCCESS'
      );
      // A different provider identity must be retained for reconciliation without completing.
      Refund_Transaction__c refund = row();
      refund.PayHub_Refund_Id__c = 'OTHER-PROVIDER-ID';
      update as system refund;
      Test.startTest();
      Integer status = RefundService.handleCallback(callback);
      Test.stopTest();
      Assert.areEqual(
        200,
        status,
        'Record contradictory receipt without applying it.'
      );
      Assert.areEqual(
        'PENDING',
        row().Status__c,
        'No unverified state update.'
      );
      Assert.areEqual(
        0,
        RefundService.eventsPublished,
        'No completion event for an unapplied result.'
      );
    }
  }

  @IsTest
  static void persistenceFailureDoesNotPublishCompletion() {
    System.runAs(RefundTestDataFactory.processor()) {
      Refund_Transaction__c refund = row();
      // Simulate another workflow changing the request before the callback is persisted.
      update as system new Return_Request__c(
        Id = refund.Return_Request__c,
        Status__c = 'REFUND_FAILED'
      );
      Test.startTest();
      Integer status = RefundService.handleCallback(
        RefundTestDataFactory.callback(refund, 'SUCCESS')
      );
      Test.stopTest();
      Assert.areEqual(
        503,
        status,
        'Ask PayHub to retry when outcome persistence fails.'
      );
      Assert.areEqual(
        'PENDING',
        row().Status__c,
        'Refund state rolls back with request transition.'
      );
      Assert.areEqual(
        0,
        RefundService.eventsPublished,
        'Never notify for rolled-back completion.'
      );
      Assert.areEqual(
        1,
        [
          SELECT COUNT()
          FROM Integration_Log__c
          WHERE Error_Code__c = 'PERSISTENCE_FAILED'
        ],
        'Retain received evidence for reconciliation.'
      );
    }
  }
  @IsTest
  static void restRejectsMissingBody() {
    System.runAs(RefundTestDataFactory.processor()) {
      RestContext.request = new RestRequest();
      RestContext.response = new RestResponse();
      Test.startTest();
      RefundCallbackRest.receive();
      Test.stopTest();
      Assert.areEqual(
        400,
        RestContext.response.statusCode,
        'Missing body is a controlled contract error.'
      );
    }
  }
  @IsTest
  static void restUnknownMerchant() {
    System.runAs(RefundTestDataFactory.processor()) {
      RefundDomain.Callback callback = RefundTestDataFactory.callback(
        row(),
        'SUCCESS'
      );
      callback.merchantRef = 'RR-UNKNOWN';
      RestRequest request = new RestRequest();
      request.requestBody = Blob.valueOf(JSON.serialize(callback));
      RestContext.request = request;
      RestContext.response = new RestResponse();
      Test.startTest();
      RefundCallbackRest.receive();
      Test.stopTest();
      Assert.areEqual(
        404,
        RestContext.response.statusCode,
        'Return BRD unknown-merchant HTTP status.'
      );
    }
  }

  @IsTest
  static void callbackReconcilesTimedOutQueuedAttempt() {
    System.runAs(RefundTestDataFactory.processor()) {
      Refund_Transaction__c refund = row();
      refund.Status__c = 'QUEUED';
      refund.Attempt_Count__c = 1;
      refund.Last_Error_Code__c = 'OUTCOME_UNCERTAIN';
      refund.Next_Retry_At__c = System.now().addMinutes(15);
      update as system refund;
      Test.startTest();
      RefundService.handleCallback(
        RefundTestDataFactory.callback(refund, 'SUCCESS')
      );
      Test.stopTest();
      Assert.areEqual(
        'SUCCEEDED',
        row().Status__c,
        'Accept delayed final result before retry dispatch.'
      );
      Assert.isNull(
        row().Next_Retry_At__c,
        'Confirmed success cancels retry eligibility.'
      );
    }
  }
}
