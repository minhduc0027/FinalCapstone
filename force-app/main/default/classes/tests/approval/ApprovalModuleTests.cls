@IsTest
private class ApprovalModuleTests {
  //===================================================
  // Test data
  //===================================================
  private static Account createCustomer(String suffix) {
    Account customer = new Account(Name = 'Approval Customer ' + suffix);

    insert customer;
    return customer;
  }

  private static Return_Request__c createRequest(
    Id customerId,
    String status,
    String approvalLevel,
    String sourceChannel,
    Decimal estimatedRefund,
    Id approverId,
    Datetime approvalDueAt
  ) {
    Return_Request__c requestRecord = new Return_Request__c(
      Customer__c = customerId,
      Status__c = status,
      Required_Approval_Level__c = approvalLevel,
      Source_Channel__c = sourceChannel,
      Estimated_Refund_Amount__c = estimatedRefund,
      ApproverId__c = approverId,
      Approval_Due_At__c = approvalDueAt
    );

    insert requestRecord;
    return requestRecord;
  }

  private static Return_Request__c createAssignedRequest(
    Id customerId,
    String status,
    String approvalLevel,
    String sourceChannel
  ) {
    return createRequest(
      customerId,
      status,
      approvalLevel,
      sourceChannel,
      5000000,
      UserInfo.getUserId(),
      System.now().addHours(24)
    );
  }

  //===================================================
  // Single approve
  //===================================================
  @IsTest
  static void approveAppRequest_ShouldMoveToAwaitingGoods() {
    Account customer = createCustomer('APP');

    Return_Request__c requestRecord = createAssignedRequest(
      customer.Id,
      SmartReturnConstants.STATUS_PENDING_APPROVAL,
      SmartReturnConstants.APPROVAL_CHT,
      SmartReturnConstants.SOURCE_APP
    );

    Test.startTest();

    ApprovalService.approveRequest(
      String.valueOf(requestRecord.Id),
      SmartReturnConstants.SOURCE_APP
    );

    Test.stopTest();

    Return_Request__c actualRequest = [
      SELECT Status__c, Required_Approval_Level__c
      FROM Return_Request__c
      WHERE Id = :requestRecord.Id
    ];

    System.assertEquals(
      SmartReturnConstants.STATUS_AWAITING_GOODS,
      actualRequest.Status__c
    );

    System.assertEquals(
      SmartReturnConstants.APPROVAL_CHT,
      actualRequest.Required_Approval_Level__c
    );
  }

  @IsTest
  static void approveStoreRequest_ShouldMoveToInspecting() {
    Account customer = createCustomer('STORE');

    Return_Request__c requestRecord = createAssignedRequest(
      customer.Id,
      SmartReturnConstants.STATUS_PENDING_APPROVAL,
      SmartReturnConstants.APPROVAL_CHT,
      SmartReturnConstants.SOURCE_STORE
    );

    Test.startTest();

    ApprovalService.approveRequest(
      String.valueOf(requestRecord.Id),
      SmartReturnConstants.SOURCE_STORE
    );

    Test.stopTest();

    Return_Request__c actualRequest = [
      SELECT Status__c
      FROM Return_Request__c
      WHERE Id = :requestRecord.Id
    ];

    System.assertEquals(
      SmartReturnConstants.STATUS_INSPECTING,
      actualRequest.Status__c
    );
  }

  //===================================================
  // Bulk approve
  //===================================================
  @IsTest
  static void approveRequestBulk_ShouldUseStoredChannels() {
    Account customer = createCustomer('BULK');

    Return_Request__c appRequest = createAssignedRequest(
      customer.Id,
      SmartReturnConstants.STATUS_PENDING_APPROVAL,
      SmartReturnConstants.APPROVAL_CHT,
      SmartReturnConstants.SOURCE_APP
    );

    Return_Request__c storeRequest = createAssignedRequest(
      customer.Id,
      SmartReturnConstants.STATUS_PENDING_APPROVAL,
      SmartReturnConstants.APPROVAL_CHT,
      SmartReturnConstants.SOURCE_STORE
    );

    Set<Id> requestIds = new Set<Id>{ appRequest.Id, storeRequest.Id };

    Test.startTest();

    ApprovalService.approveRequestBulk(new List<Id>(requestIds));

    Test.stopTest();

    Map<Id, Return_Request__c> actualById = new Map<Id, Return_Request__c>(
      [
        SELECT Id, Status__c
        FROM Return_Request__c
        WHERE Id IN :requestIds
      ]
    );

    System.assertEquals(
      SmartReturnConstants.STATUS_AWAITING_GOODS,
      actualById.get(appRequest.Id).Status__c
    );

    System.assertEquals(
      SmartReturnConstants.STATUS_INSPECTING,
      actualById.get(storeRequest.Id).Status__c
    );
  }

  @IsTest
  static void approveRequestBulk_ShouldMoveReconfirmingToRefundProcessing() {
    Account customer = createCustomer('RECONFIRM');

    Return_Request__c requestRecord = createAssignedRequest(
      customer.Id,
      SmartReturnConstants.STATUS_RE_CONFIRMING,
      SmartReturnConstants.APPROVAL_CHT,
      SmartReturnConstants.SOURCE_STORE
    );

    Test.startTest();

    ApprovalService.approveRequestBulk(new List<Id>{ requestRecord.Id });

    Test.stopTest();

    Return_Request__c actualRequest = [
      SELECT Status__c
      FROM Return_Request__c
      WHERE Id = :requestRecord.Id
    ];

    System.assertEquals(
      SmartReturnConstants.STATUS_REFUND_PROCESSING,
      actualRequest.Status__c,
      'RE_CONFIRMING phải chuyển sang REFUND_PROCESSING.'
    );
  }

  @IsTest
  static void approveRequestBulk_ShouldRejectWrongApprover() {
    Account customer = createCustomer('WRONG-APPROVER');

    User anotherUser = createTestUser('otherapprover');

    Return_Request__c requestRecord = createRequest(
      customer.Id,
      SmartReturnConstants.STATUS_PENDING_APPROVAL,
      SmartReturnConstants.APPROVAL_CHT,
      SmartReturnConstants.SOURCE_APP,
      5000000,
      anotherUser.Id,
      System.now().addHours(24)
    );

    Boolean exceptionThrown = false;

    Test.startTest();

    try {
      ApprovalService.approveRequestBulk(new List<Id>{ requestRecord.Id });
    } catch (Exception ex) {
      exceptionThrown = true;
    }

    Test.stopTest();

    System.assertEquals(
      true,
      exceptionThrown,
      'User không phải approver phải bị chặn.'
    );

    Return_Request__c unchangedRequest = [
      SELECT Status__c
      FROM Return_Request__c
      WHERE Id = :requestRecord.Id
    ];

    System.assertEquals(
      SmartReturnConstants.STATUS_PENDING_APPROVAL,
      unchangedRequest.Status__c
    );
  }

  //===================================================
  // Single reject
  //===================================================
  @IsTest
  static void rejectRequest_ShouldSaveReasonAndInternalNote() {
    Account customer = createCustomer('REJECT');

    Return_Request__c requestRecord = createAssignedRequest(
      customer.Id,
      SmartReturnConstants.STATUS_PENDING_APPROVAL,
      SmartReturnConstants.APPROVAL_CHT,
      SmartReturnConstants.SOURCE_APP
    );

    String reason = 'REQUEST_NOT_ELIGIBLE';

    String staffNote = 'Reviewed by assigned store manager.';

    Test.startTest();

    ApprovalService.rejectRequest(
      String.valueOf(requestRecord.Id),
      reason,
      staffNote
    );

    Test.stopTest();

    Return_Request__c actualRequest = [
      SELECT Status__c, Rejection_Reason__c, Internal_Notes__c
      FROM Return_Request__c
      WHERE Id = :requestRecord.Id
    ];

    System.assertEquals(
      SmartReturnConstants.STATUS_REJECTED,
      actualRequest.Status__c
    );

    System.assertEquals(reason, actualRequest.Rejection_Reason__c);

    System.assertEquals(staffNote, actualRequest.Internal_Notes__c);
  }

  @IsTest
  static void rejectRequest_ShouldRequireReason() {
    Account customer = createCustomer('NO-REASON');

    Return_Request__c requestRecord = createAssignedRequest(
      customer.Id,
      SmartReturnConstants.STATUS_PENDING_APPROVAL,
      SmartReturnConstants.APPROVAL_CHT,
      SmartReturnConstants.SOURCE_APP
    );

    Boolean exceptionThrown = false;

    Test.startTest();

    try {
      ApprovalService.rejectRequest(
        String.valueOf(requestRecord.Id),
        ' ',
        'Some note'
      );
    } catch (StateTransitionService.StateTransitionException ex) {
      exceptionThrown = true;

      System.assertEquals('Rejection reason cannot be blank.', ex.getMessage());
    }

    Test.stopTest();

    System.assertEquals(true, exceptionThrown);

    Return_Request__c unchangedRequest = [
      SELECT Status__c
      FROM Return_Request__c
      WHERE Id = :requestRecord.Id
    ];

    System.assertEquals(
      SmartReturnConstants.STATUS_PENDING_APPROVAL,
      unchangedRequest.Status__c
    );
  }

  //===================================================
  // Bulk reject
  //===================================================
  @IsTest
  static void rejectRequestBulk_ShouldRejectAllRequests() {
    Account customer = createCustomer('BULK-REJECT');

    Return_Request__c firstRequest = createAssignedRequest(
      customer.Id,
      SmartReturnConstants.STATUS_PENDING_APPROVAL,
      SmartReturnConstants.APPROVAL_CHT,
      SmartReturnConstants.SOURCE_APP
    );

    Return_Request__c secondRequest = createAssignedRequest(
      customer.Id,
      SmartReturnConstants.STATUS_PENDING_APPROVAL,
      SmartReturnConstants.APPROVAL_CHT,
      SmartReturnConstants.SOURCE_STORE
    );

    Set<Id> requestIds = new Set<Id>{ firstRequest.Id, secondRequest.Id };

    String reason = 'MANAGER_REJECTED';

    String staffNote = 'Bulk rejection from worklist.';

    Test.startTest();

    ApprovalService.rejectRequestBulk(
      new List<Id>(requestIds),
      reason,
      staffNote
    );

    Test.stopTest();

    List<Return_Request__c> actualRequests = [
      SELECT Status__c, Rejection_Reason__c, Internal_Notes__c
      FROM Return_Request__c
      WHERE Id IN :requestIds
    ];

    System.assertEquals(2, actualRequests.size());

    for (Return_Request__c actualRequest : actualRequests) {
      System.assertEquals(
        SmartReturnConstants.STATUS_REJECTED,
        actualRequest.Status__c
      );

      System.assertEquals(reason, actualRequest.Rejection_Reason__c);

      System.assertEquals(staffNote, actualRequest.Internal_Notes__c);
    }
  }

  //===================================================
  // Approval routing
  //===================================================
  @IsTest
  static void initialRouting_ShouldAssignChtForStoreRange() {
    Account customer = createCustomer('ROUTING-CHT');

    Decimal autoLimit = SmartReturnConfigService.getAutoApprovalLimit();

    Decimal storeLimit = SmartReturnConfigService.getStoreApprovalLimit();

    Decimal estimatedRefund = autoLimit + 1;

    System.assert(
      estimatedRefund <= storeLimit,
      'Store limit phải lớn hơn auto limit.'
    );

    Return_Request__c requestRecord = createRequest(
      customer.Id,
      SmartReturnConstants.STATUS_NEW,
      null,
      SmartReturnConstants.SOURCE_APP,
      estimatedRefund,
      null,
      null
    );

    Test.startTest();

    ApprovalRoutingService.evaluateInitialStatus(requestRecord);

    Test.stopTest();

    Return_Request__c actualRequest = [
      SELECT Status__c, Required_Approval_Level__c, Approval_Due_At__c
      FROM Return_Request__c
      WHERE Id = :requestRecord.Id
    ];

    System.assertEquals(
      SmartReturnConstants.STATUS_PENDING_APPROVAL,
      actualRequest.Status__c
    );

    System.assertEquals(
      SmartReturnConstants.APPROVAL_CHT,
      actualRequest.Required_Approval_Level__c
    );

    System.assertNotEquals(null, actualRequest.Approval_Due_At__c);
  }

  @IsTest
  static void initialRouting_ShouldAssignQlvAboveStoreLimit() {
    Account customer = createCustomer('ROUTING-QLV');

    Decimal storeLimit = SmartReturnConfigService.getStoreApprovalLimit();

    Return_Request__c requestRecord = createRequest(
      customer.Id,
      SmartReturnConstants.STATUS_NEW,
      null,
      SmartReturnConstants.SOURCE_APP,
      storeLimit + 1,
      null,
      null
    );

    Test.startTest();

    ApprovalRoutingService.evaluateInitialStatus(requestRecord);

    Test.stopTest();

    Return_Request__c actualRequest = [
      SELECT Status__c, Required_Approval_Level__c
      FROM Return_Request__c
      WHERE Id = :requestRecord.Id
    ];

    System.assertEquals(
      SmartReturnConstants.STATUS_PENDING_APPROVAL,
      actualRequest.Status__c
    );

    System.assertEquals(
      SmartReturnConstants.APPROVAL_QLV,
      actualRequest.Required_Approval_Level__c
    );
  }

  //===================================================
  // Transition metadata
  //===================================================
  @IsTest
  static void transitionToPendingApproval_ShouldSetDeadline() {
    Account customer = createCustomer('DEADLINE');

    Return_Request__c requestRecord = createRequest(
      customer.Id,
      SmartReturnConstants.STATUS_NEW,
      null,
      SmartReturnConstants.SOURCE_APP,
      5000000,
      null,
      null
    );

    Test.startTest();

    StateTransitionService.transition(
      requestRecord.Id,
      SmartReturnConstants.STATUS_PENDING_APPROVAL,
      SmartReturnConstants.APPROVAL_CHT
    );

    Test.stopTest();

    Return_Request__c actualRequest = [
      SELECT Status__c, Approval_Due_At__c
      FROM Return_Request__c
      WHERE Id = :requestRecord.Id
    ];

    System.assertEquals(
      SmartReturnConstants.STATUS_PENDING_APPROVAL,
      actualRequest.Status__c
    );

    System.assertNotEquals(null, actualRequest.Approval_Due_At__c);
  }

  //===================================================
  // User factory
  //===================================================
  private static User createTestUser(String uniqueSuffix) {
    String uniqueValue =
      uniqueSuffix + String.valueOf(Datetime.now().getTime());

    User testUser = new User(
      FirstName = 'Approval',
      LastName = 'Tester',
      Alias = uniqueValue.left(8),
      Email = uniqueValue + '@example.test',
      Username = uniqueValue + '@example.test',
      CommunityNickname = uniqueValue.left(30),
      TimeZoneSidKey = 'Asia/Ho_Chi_Minh',
      LocaleSidKey = 'en_US',
      EmailEncodingKey = 'UTF-8',
      LanguageLocaleKey = 'en_US',
      ProfileId = UserInfo.getProfileId()
    );

    insert testUser;
    return testUser;
  }
}
