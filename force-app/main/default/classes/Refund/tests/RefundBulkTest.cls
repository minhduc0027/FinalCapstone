@IsTest
private class RefundBulkTest {
  @TestSetup
  static void setup() {
    User actor = RefundTestDataFactory.grantProcessor();
    System.runAs(actor) {
      RefundTestDataFactory.requests(10, 'REFUND_PROCESSING', true);
    }
  }

  @IsTest
  static void oneWorkerProcessesTenRefunds() {
    System.runAs(RefundTestDataFactory.processor()) {
      List<Refund_Transaction__c> refunds = new List<Refund_Transaction__c>();
      for (Return_Request__c request : [SELECT Id FROM Return_Request__c]) {
        refunds.add(RefundTestDataFactory.refund(request.Id, 'QUEUED'));
      }
      Set<Id> ids = new Map<Id, Refund_Transaction__c>(refunds).keySet();
      Test.setMock(
        HttpCalloutMock.class,
        new RefundTestDataFactory.Mock('SUCCESS')
      );

      Test.startTest();
      RefundService.claimRefunds(ids);
      Set<String> workers = new Set<String>();
      for (Refund_Transaction__c claimed : RefundSelector.byIds(ids, false)) {
        workers.add(claimed.Worker_Job_Id__c);
      }
      Assert.areEqual(1, workers.size(), 'Ten refunds share one worker.');
      Test.stopTest();

      for (Refund_Transaction__c completed : RefundSelector.byIds(ids, false)) {
        Assert.areEqual(
          'SUCCEEDED',
          completed.Status__c,
          'Every refund finishes.'
        );
      }
      Assert.areEqual(
        10,
        [SELECT COUNT() FROM Integration_Log__c],
        'Every PayHub call has an audit entry.'
      );
    }
  }
}
