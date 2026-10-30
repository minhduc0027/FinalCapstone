@IsTest
private class RefundAccountingTest {
  @TestSetup
  static void setup() {
    RefundTestDataFactory.setupAccountingRefunds();
  }

  private static User accountant() {
    return [
      SELECT Id
      FROM User
      WHERE LastName = 'Refund Test Accountant'
      LIMIT 1
    ];
  }

  private static Refund_Transaction__c refund() {
    return [
      SELECT Id, Return_Request__c, Accounting_Task_Id__c
      FROM Refund_Transaction__c
      LIMIT 1
    ];
  }

  @IsTest
  static void readOnlyAccountantCompletesRequestAndTask() {
    Refund_Transaction__c original = refund();
    User actor = accountant();
    System.runAs(actor) {
      Assert.isFalse(
        Schema.SObjectType.Order.isAccessible(),
        'Do not rely on Order access.'
      );
      Assert.isFalse(
        Schema.SObjectType.Return_Request__c.isUpdateable(),
        'Normal request access stays read-only.'
      );
      Assert.isFalse(
        Schema.SObjectType.Refund_Transaction__c.isUpdateable(),
        'Normal refund access stays read-only.'
      );
      Test.startTest();
      RefundService.manualComplete(original.Id, 'BANK-001');
      Test.stopTest();
    }
    Refund_Transaction__c saved = [
      SELECT
        Status__c,
        Manual_Reference__c,
        Manual_Completed_By__c,
        Manual_Completed_At__c,
        Needs_Reconciliation__c
      FROM Refund_Transaction__c
      WHERE Id = :original.Id
    ];
    Assert.areEqual(
      'COMPLETED',
      [
        SELECT Status__c
        FROM Return_Request__c
        WHERE Id = :original.Return_Request__c
      ]
      .Status__c,
      'Complete the return request.'
    );
    Assert.areEqual(
      'FAILED',
      saved.Status__c,
      'Preserve the provider failure.'
    );
    Assert.areEqual(
      'BANK-001',
      saved.Manual_Reference__c,
      'Save the external transaction reference.'
    );
    Assert.areEqual(
      actor.Id,
      saved.Manual_Completed_By__c,
      'Save the accountant actor.'
    );
    Assert.isNotNull(
      saved.Manual_Completed_At__c,
      'Save the manual completion time.'
    );
    Assert.isFalse(
      saved.Needs_Reconciliation__c,
      'Remove from the reconciliation work list.'
    );
    Assert.areEqual(
      'Completed',
      [SELECT Status FROM Task WHERE Id = :original.Accounting_Task_Id__c]
      .Status,
      'Close the accounting queue task.'
    );
  }

  @IsTest
  static void sameReferenceDoesNotRepeatCompletion() {
    Refund_Transaction__c original = refund();
    System.runAs(accountant()) {
      Test.startTest();
      RefundService.manualComplete(original.Id, 'BANK-002');
      Datetime completedAt = [
        SELECT Manual_Completed_At__c
        FROM Refund_Transaction__c
        WHERE Id = :original.Id
      ]
      .Manual_Completed_At__c;
      RefundService.manualComplete(original.Id, 'BANK-002');
      Assert.areEqual(
        completedAt,
        [
          SELECT Manual_Completed_At__c
          FROM Refund_Transaction__c
          WHERE Id = :original.Id
        ]
        .Manual_Completed_At__c,
        'Keep the original completion audit.'
      );
      Assert.areEqual(
        1,
        RefundService.notificationEventsQueued,
        'Queue completion notification once.'
      );
      Assert.areEqual(0, Limits.getCallouts(), 'Do not issue another payment.');
      Test.stopTest();
    }
  }

  @IsTest
  static void differentReferenceCannotOverwriteCompletion() {
    Refund_Transaction__c original = refund();
    System.runAs(accountant()) {
      Test.startTest();
      RefundService.manualComplete(original.Id, 'BANK-003');
      try {
        RefundService.manualComplete(original.Id, 'BANK-004');
        Assert.fail('Do not overwrite a completed manual refund.');
      } catch (RefundService.RefundException e) {
        Assert.isTrue(
          e.getMessage().contains('Only a failed refund'),
          'Explain that this refund no longer qualifies.'
        );
      }
      Test.stopTest();
    }
    Assert.areEqual(
      'BANK-003',
      [
        SELECT Manual_Reference__c
        FROM Refund_Transaction__c
        WHERE Id = :original.Id
      ]
      .Manual_Reference__c,
      'Preserve the original transaction reference.'
    );
  }
  @IsTest
  static void persistenceBoundaryRequiresAccountingPermission() {
    Refund_Transaction__c original = refund();
    Return_Request__c request = [
      SELECT Id, Status__c
      FROM Return_Request__c
      WHERE Id = :original.Return_Request__c
    ];
    System.runAs(RefundTestDataFactory.processor()) {
      Test.startTest();
      try {
        RefundManualCompletionService.complete(original, request, 'BANK-005');
        Assert.fail('The processor cannot invoke Accounting persistence.');
      } catch (RefundService.RefundException e) {
        Assert.isTrue(
          e.getMessage().contains('do not have permission'),
          'Require the Accounting operation permission.'
        );
      }
      Test.stopTest();
    }
    Assert.areEqual(
      'REFUND_FAILED',
      [
        SELECT Status__c
        FROM Return_Request__c
        WHERE Id = :original.Return_Request__c
      ]
      .Status__c,
      'Keep the request unchanged.'
    );
  }
}
