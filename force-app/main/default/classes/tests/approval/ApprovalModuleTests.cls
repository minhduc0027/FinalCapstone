@IsTest
private class ApprovalModuleTests {
  private static final String APPROVER_LAST_NAME = 'Return Request Test Approver';

  @TestSetup
  static void setupUsers() {
    ReturnRequestTestDataFactory.createApprover();
  }

  private static User getApprover() {
    return [
      SELECT Id
      FROM User
      WHERE LastName = :APPROVER_LAST_NAME
      LIMIT 1
    ];
  }

  private static Account createCustomer(String suffix) {
    Account customer = new Account(Name = 'Approval Test Customer ' + suffix);

    insert customer;
    return customer;
  }

  private static Return_Request__c createRequest(
    Id customerId,
    String status,
    String approvalLevel,
    String channel,
    Decimal amount,
    Id approverId,
    Datetime dueAt
  ) {
    Return_Request__c requestRecord = ReturnRequestTestDataFactory.requests(
      1,
      customerId
    )[0];

    requestRecord.Status__c = status;
    requestRecord.Required_Approval_Level__c = approvalLevel;
    requestRecord.Source_Channel__c = channel;
    requestRecord.Estimated_Refund_Amount__c = amount;
    requestRecord.ApproverId__c = approverId;
    requestRecord.Approval_Due_At__c = dueAt;

    insert as system requestRecord;

    return requestRecord;
  }

  @IsTest
  static void approveBulk_ShouldRouteByStoredChannel() {
    User approver = getApprover();
    Account customer = createCustomer('CHANNEL');

    Return_Request__c appRequest = createRequest(
      customer.Id,
      SmartReturnConstants.STATUS_PENDING_APPROVAL,
      SmartReturnConstants.APPROVAL_CHT,
      SmartReturnConstants.SOURCE_APP,
      5000000,
      approver.Id,
      System.now().addHours(24)
    );

    Return_Request__c posRequest = createRequest(
      customer.Id,
      SmartReturnConstants.STATUS_PENDING_APPROVAL,
      SmartReturnConstants.APPROVAL_CHT,
      SmartReturnConstants.SOURCE_POS,
      5000000,
      approver.Id,
      System.now().addHours(24)
    );

    System.runAs(approver) {
      Test.startTest();

      List<ApprovalActionResult> results = ApprovalController.bulkApprove(
        new List<Id>{ appRequest.Id, posRequest.Id }
      );

      Test.stopTest();

      System.assertEquals(2, results.size());
      System.assertEquals(true, results[0].success);
      System.assertEquals(true, results[1].success);
    }

    Map<Id, Return_Request__c> actualById = new Map<Id, Return_Request__c>(
      [
        SELECT Id, Status__c
        FROM Return_Request__c
        WHERE Id IN :new Set<Id>{ appRequest.Id, posRequest.Id }
      ]
    );

    System.assertEquals(
      SmartReturnConstants.STATUS_AWAITING_GOODS,
      actualById.get(appRequest.Id).Status__c
    );

    System.assertEquals(
      SmartReturnConstants.STATUS_INSPECTING,
      actualById.get(posRequest.Id).Status__c
    );
  }

  @IsTest
  static void approveReconfirming_ShouldMoveToRefundProcessing() {
    User approver = getApprover();
    Account customer = createCustomer('RECONFIRM');

    Return_Request__c requestRecord = createRequest(
      customer.Id,
      SmartReturnConstants.STATUS_RE_CONFIRMING,
      SmartReturnConstants.APPROVAL_CHT,
      SmartReturnConstants.SOURCE_POS,
      5000000,
      approver.Id,
      null
    );

    System.runAs(approver) {
      Test.startTest();

      ApprovalService.approveRequest(requestRecord.Id);

      Test.stopTest();
    }

    Return_Request__c actual = [
      SELECT Status__c
      FROM Return_Request__c
      WHERE Id = :requestRecord.Id
    ];

    System.assertEquals(
      SmartReturnConstants.STATUS_REFUND_PROCESSING,
      actual.Status__c
    );
  }

  @IsTest
  static void approveBulk_ShouldReturnPartialSuccess() {
    User approver = getApprover();
    User wrongApprover = createAdditionalUser('wrong');
    Account customer = createCustomer('PARTIAL');

    Return_Request__c allowed = createRequest(
      customer.Id,
      SmartReturnConstants.STATUS_PENDING_APPROVAL,
      SmartReturnConstants.APPROVAL_CHT,
      SmartReturnConstants.SOURCE_APP,
      5000000,
      approver.Id,
      System.now().addHours(24)
    );

    Return_Request__c denied = createRequest(
      customer.Id,
      SmartReturnConstants.STATUS_PENDING_APPROVAL,
      SmartReturnConstants.APPROVAL_CHT,
      SmartReturnConstants.SOURCE_APP,
      5000000,
      wrongApprover.Id,
      System.now().addHours(24)
    );

    List<ApprovalActionResult> results;

    System.runAs(approver) {
      Test.startTest();

      results = ApprovalService.approveRequestBulk(
        new List<Id>{ allowed.Id, denied.Id }
      );

      Test.stopTest();
    }

    System.assertEquals(2, results.size());
    System.assertEquals(true, results[0].success);
    System.assertEquals(false, results[1].success);

    Map<Id, Return_Request__c> actualById = new Map<Id, Return_Request__c>(
      [
        SELECT Id, Status__c
        FROM Return_Request__c
        WHERE Id IN :new Set<Id>{ allowed.Id, denied.Id }
      ]
    );

    System.assertEquals(
      SmartReturnConstants.STATUS_AWAITING_GOODS,
      actualById.get(allowed.Id).Status__c
    );

    System.assertEquals(
      SmartReturnConstants.STATUS_PENDING_APPROVAL,
      actualById.get(denied.Id).Status__c
    );
  }

  @IsTest
  static void rejectBulk_ShouldPersistReasonAndNote() {
    User approver = getApprover();
    Account customer = createCustomer('REJECT');

    Return_Request__c requestRecord = createRequest(
      customer.Id,
      SmartReturnConstants.STATUS_PENDING_APPROVAL,
      SmartReturnConstants.APPROVAL_CHT,
      SmartReturnConstants.SOURCE_APP,
      5000000,
      approver.Id,
      System.now().addHours(24)
    );

    System.runAs(approver) {
      Test.startTest();

      List<ApprovalActionResult> results = ApprovalController.bulkReject(
        new List<Id>{ requestRecord.Id },
        'REQUEST_NOT_ELIGIBLE',
        'Reviewed by assigned approver.'
      );

      Test.stopTest();

      System.assertEquals(true, results[0].success);
    }

    Return_Request__c actual = [
      SELECT Status__c, Rejection_Reason__c, Internal_Notes__c
      FROM Return_Request__c
      WHERE Id = :requestRecord.Id
    ];

    System.assertEquals(SmartReturnConstants.STATUS_REJECTED, actual.Status__c);

    System.assertEquals('REQUEST_NOT_ELIGIBLE', actual.Rejection_Reason__c);

    System.assertEquals(
      'Reviewed by assigned approver.',
      actual.Internal_Notes__c
    );
  }

  @IsTest
  static void reject_ShouldRequireReason() {
    Boolean thrown = false;

    Test.startTest();

    try {
      ApprovalController.bulkReject(
        new List<Id>{ UserInfo.getUserId() },
        ' ',
        null
      );
    } catch (AuraHandledException ex) {
      thrown = true;
    }

    Test.stopTest();

    System.assertEquals(true, thrown);
  }

  @IsTest
  static void approvalRouting_ShouldRouteRiskCustomerToQlv() {
    Account customer = createCustomer('RISK');

    Integer threshold = SmartReturnConfigService.getRiskRequestCount();

    List<Return_Request__c> previous = new List<Return_Request__c>();

    for (Integer index = 0; index < threshold - 1; index++) {
      previous.add(
        createRequest(
          customer.Id,
          SmartReturnConstants.STATUS_COMPLETED,
          SmartReturnConstants.APPROVAL_CHT,
          SmartReturnConstants.SOURCE_APP,
          100000,
          null,
          null
        )
      );
    }

    Return_Request__c currentRequest = createRequest(
      customer.Id,
      SmartReturnConstants.STATUS_NEW,
      null,
      SmartReturnConstants.SOURCE_APP,
      100000,
      null,
      null
    );

    Test.startTest();

    ApprovalRoutingService.evaluateInitialStatus(currentRequest);

    Test.stopTest();

    Return_Request__c actual = [
      SELECT Status__c, Required_Approval_Level__c
      FROM Return_Request__c
      WHERE Id = :currentRequest.Id
    ];

    System.assertEquals(
      SmartReturnConstants.STATUS_PENDING_APPROVAL,
      actual.Status__c
    );

    System.assertEquals(
      SmartReturnConstants.APPROVAL_QLV,
      actual.Required_Approval_Level__c,
      'Request hiện tại phải được tính vào risk threshold.'
    );
  }

  @IsTest
  static void escalationBatch_ShouldAssignRegionalManager() {
    User regionalManager = createAdditionalUser('region');
    Account customer = createCustomer('ESCALATE');

    Store__c store = new Store__c(
      Store_Code__c = 'ESC-STORE',
      Region_Manager__c = regionalManager.Id
    );
    insert store;

    Return_Request__c requestRecord = createRequest(
      customer.Id,
      SmartReturnConstants.STATUS_PENDING_APPROVAL,
      SmartReturnConstants.APPROVAL_CHT,
      SmartReturnConstants.SOURCE_APP,
      5000000,
      getApprover().Id,
      System.now().addHours(-1)
    );

    requestRecord.Store__c = store.Id;
    update requestRecord;

    Test.startTest();

    Database.executeBatch(new ApprovalEscalationBatch(), 200);

    Test.stopTest();

    Return_Request__c actual = [
      SELECT
        Status__c,
        Required_Approval_Level__c,
        ApproverId__c,
        Approval_Due_At__c
      FROM Return_Request__c
      WHERE Id = :requestRecord.Id
    ];

    System.assertEquals(
      SmartReturnConstants.STATUS_PENDING_APPROVAL,
      actual.Status__c
    );

    System.assertEquals(
      SmartReturnConstants.APPROVAL_QLV,
      actual.Required_Approval_Level__c
    );

    System.assertEquals(regionalManager.Id, actual.ApproverId__c);

    System.assertEquals(null, actual.Approval_Due_At__c);
  }

  private static User createAdditionalUser(String suffix) {
    String uniqueValue = suffix + String.valueOf(Datetime.now().getTime());

    User userRecord = new User(
      FirstName = 'SmartReturn',
      LastName = 'Approver ' + suffix,
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

    insert userRecord;
    return userRecord;
  }
}
