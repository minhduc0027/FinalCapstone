@IsTest
private class ApprovalWorklistTests {
  private static Account createCustomer() {
    Account customer = new Account(Name = 'Worklist Customer');
    insert customer;
    return customer;
  }

  private static Return_Request__c createRequest(
    Id customerId,
    String status,
    String approvalLevel
  ) {
    Return_Request__c requestRecord = ReturnRequestTestDataFactory.requests(
      1,
      customerId
    )[0];
    requestRecord.Status__c = status;
    requestRecord.Required_Approval_Level__c = approvalLevel;
    requestRecord.Source_Channel__c = SmartReturnConstants.SOURCE_APP;
    requestRecord.Estimated_Refund_Amount__c = 1000000;
    requestRecord.ApproverId__c = UserInfo.getUserId();
    if (status == SmartReturnConstants.STATUS_REJECTED)
      requestRecord.Rejection_Reason__c = 'Test rejection reason';
    insert as system requestRecord;
    return requestRecord;
  }

  @IsTest
  static void getWorklist_ShouldReturnPendingApprovalRequests() {
    Account customer = createCustomer();

    createRequest(
      customer.Id,
      SmartReturnConstants.STATUS_PENDING_APPROVAL,
      SmartReturnConstants.APPROVAL_CHT
    );
    createRequest(
      customer.Id,
      SmartReturnConstants.STATUS_REJECTED,
      SmartReturnConstants.APPROVAL_CHT
    );
    ApprovalFilter filter = new ApprovalFilter();
    filter.assignedToMe = true;

    Test.startTest();
    ApprovalPageResult result = ApprovalService.getWorklist(filter);
    Test.stopTest();

    System.assertNotEquals(null, result);
    System.assertEquals(
      1,
      result.records.size(),
      'Chỉ request PENDING_APPROVAL được trả về.'
    );
    System.assertEquals(
      SmartReturnConstants.STATUS_PENDING_APPROVAL,
      result.records[0].status
    );
  }

  @IsTest
  static void getWorklist_ShouldFilterByApprovalLevel() {
    Account customer = createCustomer();

    createRequest(
      customer.Id,
      SmartReturnConstants.STATUS_PENDING_APPROVAL,
      SmartReturnConstants.APPROVAL_CHT
    );

    createRequest(
      customer.Id,
      SmartReturnConstants.STATUS_PENDING_APPROVAL,
      SmartReturnConstants.APPROVAL_QLV
    );

    ApprovalFilter filter = new ApprovalFilter();
    filter.status = SmartReturnConstants.STATUS_PENDING_APPROVAL;
    filter.approvalLevel = SmartReturnConstants.APPROVAL_QLV;

    Test.startTest();
    ApprovalPageResult result = ApprovalService.getWorklist(filter);
    Test.stopTest();

    System.assertEquals(1, result.records.size());
    System.assertEquals(
      SmartReturnConstants.APPROVAL_QLV,
      result.records[0].approvalLevel
    );
  }

  @IsTest
  static void getWorklist_ShouldRejectUnsupportedStatus() {
    ApprovalFilter filter = new ApprovalFilter();

    filter.status = SmartReturnConstants.STATUS_COMPLETED;

    Boolean exceptionThrown = false;
    Test.startTest();
    try {
      ApprovalService.getWorklist(filter);
    } catch (AuraHandledException ex) {
      exceptionThrown = true;
    }
    Test.stopTest();
    System.assertEquals(true, exceptionThrown);
  }
}
