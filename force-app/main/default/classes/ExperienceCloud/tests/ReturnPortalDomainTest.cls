@IsTest
private class ReturnPortalDomainTest {
  @IsTest
  static void failedPaymentDoesNotBecomeCompletedInPresentation() {
    Return_Request__c row = (Return_Request__c) JSON.deserialize(
      '{"Name":"RR-2610-00001","Status__c":"REFUND_FAILED","CreatedDate":"2026-10-01T00:00:00Z","Actual_Refund_Amount__c":1992000,"Estimated_Refund_Amount__c":2490000}',
      Return_Request__c.class
    );
    Test.startTest();
    PortalReturn result = ReturnPortalDomain.project(row, true);
    Test.stopTest();
    Assert.areEqual(
      'REFUND_FAILED',
      result.status,
      'An actual amount is not proof of successful payment.'
    );
    Assert.areEqual(
      1992000,
      result.refundAmount,
      'Use the actual amount after inspection.'
    );
    Assert.areEqual(
      'ACTUAL',
      result.amountKind,
      'Keep the amount basis explicit.'
    );
  }

  @IsTest
  static void oldRequestNumberIsAccepted() {
    Test.startTest();
    String normalizedNumber = ReturnPortalDomain.normalizeNumber(' rr-000001 ');
    Test.stopTest();
    Assert.areEqual(
      'RR-000001',
      normalizedNumber,
      'Existing customer references must survive the new numbering format.'
    );
  }

  @IsTest
  static void invalidPolicyIsRejected() {
    Test.startTest();
    try {
      new ReturnPortalDomain.LookupPolicy(0, 15, 15);
      Assert.fail('An invalid policy must not silently disable lockout.');
    } catch (ReturnPortalDomain.PortalException e) {
      Assert.isTrue(
        e.getMessage().contains('Cấu hình'),
        'Explain the configuration error.'
      );
    }
    Test.stopTest();
  }

  @IsTest
  static void failureWindowExpiresAtTheBoundary() {
    Datetime nowTime = System.now();
    Portal_Lookup_Limit__c counter = new Portal_Lookup_Limit__c(
      Window_Started_At__c = nowTime.addMinutes(-15),
      Failure_Count__c = 4
    );
    Test.startTest();
    ReturnPortalDomain.recordFailure(
      counter,
      new ReturnPortalDomain.LookupPolicy(5, 15, 15),
      nowTime
    );
    Test.stopTest();
    Assert.areEqual(
      1,
      counter.Failure_Count__c,
      'A failure at the boundary starts a new window.'
    );
    Assert.isNull(
      counter.Locked_Until__c,
      'An expired window must not inherit four old guesses.'
    );
  }
}
