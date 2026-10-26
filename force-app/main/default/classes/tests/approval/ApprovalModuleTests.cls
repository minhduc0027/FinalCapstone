@IsTest
private class ApprovalModuleTests {
  private static final String APPROVER_LAST_NAME = 'Return Request Test Approver';

  //===================================================
  // Test setup
  //===================================================
  @TestSetup
  static void setupApprover() {
    ReturnRequestTestDataFactory.createApprover();
  }

  private static User getApprover() {
    return [
      SELECT Id, LastName
      FROM User
      WHERE LastName = :APPROVER_LAST_NAME
      LIMIT 1
    ];
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

    insert as system userRecord;
    return userRecord;
  }

  //===================================================
  // Test-data helpers
  //===================================================
  private static Account createCustomer(String suffix) {
    Account customer = new Account(Name = 'Approval Test Customer ' + suffix);

    insert as system customer;
    return customer;
  }

  private static Store__c createStore(Id storeManagerId, Id regionalManagerId) {
    Store__c storeRecord = new Store__c(
      Name = 'Approval Test Store ',
      Store_Code__c = 'STORE123456789TEST',
      Store_Manager__c = storeManagerId,
      Region_Manager__c = regionalManagerId
    );

    insert as system storeRecord;
    return storeRecord;
  }

  private static Order createOrder(Id customerId, Id storeId) {
    Order orderRecord = new Order(
      AccountId = customerId,
      Store__c = storeId,
      EffectiveDate = Date.today(),
      Status = 'Draft'
    );

    insert as system orderRecord;
    return orderRecord;
  }

  /**
   * Request được tạo bởi test-running user.
   * Approver là user khác, tránh vi phạm self-approval.
   */
  private static Return_Request__c createRequest(
    Id customerId,
    String status,
    String approvalLevel,
    String sourceChannel,
    Decimal estimatedAmount,
    Id approverId,
    Datetime approvalDueAt,
    Id regionalManagerId,
    String suffix
  ) {
    Id effectiveStoreManagerId = approverId == null
      ? UserInfo.getUserId()
      : approverId;

    Id effectiveRegionalManagerId = regionalManagerId == null
      ? effectiveStoreManagerId
      : regionalManagerId;

    Store__c storeRecord = createStore(
      effectiveStoreManagerId,
      effectiveRegionalManagerId
    );

    Order orderRecord = createOrder(customerId, storeRecord.Id);

    Return_Request__c requestRecord = new Return_Request__c(
      Customer__c = customerId,
      Order__c = orderRecord.Id,
      Store__c = storeRecord.Id,
      Status__c = status,
      Required_Approval_Level__c = approvalLevel,
      Source_Channel__c = sourceChannel,
      Estimated_Refund_Amount__c = estimatedAmount,
      ApproverId__c = approverId,
      Approval_Due_At__c = approvalDueAt
    );

    insert as system requestRecord;

    /*
     * Query lại để test fixture phản ánh chính xác
     * dữ liệu sau trigger/flow.
     */
    Return_Request__c persistedRequest = [
      SELECT
        Id,
        Status__c,
        Required_Approval_Level__c,
        Source_Channel__c,
        ApproverId__c,
        Approval_Due_At__c,
        CreatedById,
        Store__c,
        Store__r.Store_Manager__c,
        Store__r.Region_Manager__c
      FROM Return_Request__c
      WHERE Id = :requestRecord.Id
      WITH SYSTEM_MODE
    ];

    /*
     * Chỉ assert cho manual-approval fixtures.
     * Routing fixtures có thể chưa có approver.
     */
    if (approverId != null) {
      System.assertEquals(
        approverId,
        persistedRequest.ApproverId__c,
        'ApproverId__c đã bị automation thay đổi khi insert.'
      );

      System.assertEquals(
        approverId,
        persistedRequest.Store__r.Store_Manager__c,
        'Store Manager phải khớp approver của test.'
      );
    }

    return persistedRequest;
  }

  private static Return_Request__c createAssignedRequest(
    Id customerId,
    String status,
    String approvalLevel,
    String sourceChannel,
    Id approverId,
    String suffix
  ) {
    return createRequest(
      customerId,
      status,
      approvalLevel,
      sourceChannel,
      5000000,
      approverId,
      System.now().addHours(24),
      approverId,
      suffix
    );
  }

  private static Map<Id, ApprovalActionResult> resultsByRequestId(
    List<ApprovalActionResult> results
  ) {
    Map<Id, ApprovalActionResult> resultById = new Map<Id, ApprovalActionResult>();

    for (ApprovalActionResult item : results) {
      if (item.requestId != null) {
        resultById.put(item.requestId, item);
      }
    }

    return resultById;
  }

  //===================================================
  // Bulk approve by stored Source Channel
  //===================================================
  @IsTest
  static void approveBulk_ShouldRouteByStoredChannel() {
    User approver = getApprover();
    Account customer = createCustomer('CHANNEL');

    Return_Request__c appRequest = createAssignedRequest(
      customer.Id,
      SmartReturnConstants.STATUS_PENDING_APPROVAL,
      SmartReturnConstants.APPROVAL_CHT,
      SmartReturnConstants.SOURCE_APP,
      approver.Id,
      'APP'
    );

    Return_Request__c posRequest = createAssignedRequest(
      customer.Id,
      SmartReturnConstants.STATUS_PENDING_APPROVAL,
      SmartReturnConstants.APPROVAL_CHT,
      SmartReturnConstants.SOURCE_POS,
      approver.Id,
      'POS'
    );

    List<ApprovalActionResult> results;

    System.runAs(approver) {
      Test.startTest();

      results = ApprovalController.bulkApprove(
        new List<Id>{ appRequest.Id, posRequest.Id }
      );

      Test.stopTest();
    }

    System.assertEquals(2, results.size());

    Map<Id, ApprovalActionResult> resultById = resultsByRequestId(results);

    System.assertEquals(
      true,
      resultById.get(appRequest.Id).success,
      'APP approval failed: ' + resultById.get(appRequest.Id).message
    );

    System.assertEquals(
      true,
      resultById.get(posRequest.Id).success,
      'POS approval failed: ' + resultById.get(posRequest.Id).message
    );

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

  //===================================================
  // RE_CONFIRMING approval
  //===================================================
  @IsTest
  static void approveReconfirming_ShouldMoveToRefundProcessing() {
    User approver = getApprover();
    Account customer = createCustomer('RECONFIRM');

    Return_Request__c requestRecord = createAssignedRequest(
      customer.Id,
      SmartReturnConstants.STATUS_RE_CONFIRMING,
      SmartReturnConstants.APPROVAL_CHT,
      SmartReturnConstants.SOURCE_POS,
      approver.Id,
      'RECONFIRM'
    );

    System.runAs(approver) {
      Test.startTest();

      ApprovalService.approveRequest(requestRecord.Id);

      Test.stopTest();
    }

    Return_Request__c actualRequest = [
      SELECT Status__c
      FROM Return_Request__c
      WHERE Id = :requestRecord.Id
    ];

    System.assertEquals(
      SmartReturnConstants.STATUS_REFUND_PROCESSING,
      actualRequest.Status__c
    );
  }

  //===================================================
  // Partial success
  //===================================================
  @IsTest
  static void approveBulk_ShouldReturnPartialSuccess() {
    User approver = getApprover();

    User wrongApprover = createAdditionalUser('wrong');

    Account customer = createCustomer('PARTIAL');

    Return_Request__c allowedRequest = createAssignedRequest(
      customer.Id,
      SmartReturnConstants.STATUS_PENDING_APPROVAL,
      SmartReturnConstants.APPROVAL_CHT,
      SmartReturnConstants.SOURCE_APP,
      approver.Id,
      'ALLOWED'
    );

    Return_Request__c deniedRequest = createAssignedRequest(
      customer.Id,
      SmartReturnConstants.STATUS_PENDING_APPROVAL,
      SmartReturnConstants.APPROVAL_CHT,
      SmartReturnConstants.SOURCE_APP,
      wrongApprover.Id,
      'DENIED'
    );

    List<ApprovalActionResult> results;

    System.runAs(approver) {
      Test.startTest();

      results = ApprovalService.approveRequestBulk(
        new List<Id>{ allowedRequest.Id, deniedRequest.Id }
      );

      Test.stopTest();
    }

    System.assertEquals(2, results.size());

    Map<Id, ApprovalActionResult> resultById = resultsByRequestId(results);

    System.assertEquals(
      true,
      resultById.get(allowedRequest.Id).success,
      'Allowed request failed: ' + resultById.get(allowedRequest.Id).message
    );

    System.assertEquals(
      false,
      resultById.get(deniedRequest.Id).success,
      'Request assigned to another approver phải fail.'
    );

    Map<Id, Return_Request__c> actualById = new Map<Id, Return_Request__c>(
      [
        SELECT Id, Status__c
        FROM Return_Request__c
        WHERE Id IN :new Set<Id>{ allowedRequest.Id, deniedRequest.Id }
      ]
    );

    System.assertEquals(
      SmartReturnConstants.STATUS_AWAITING_GOODS,
      actualById.get(allowedRequest.Id).Status__c
    );

    System.assertEquals(
      SmartReturnConstants.STATUS_PENDING_APPROVAL,
      actualById.get(deniedRequest.Id).Status__c
    );
  }

  //===================================================
  // Bulk reject
  //===================================================
  @IsTest
  static void rejectBulk_ShouldPersistReasonAndNote() {
    User approver = getApprover();
    Account customer = createCustomer('REJECT');

    Return_Request__c requestRecord = createAssignedRequest(
      customer.Id,
      SmartReturnConstants.STATUS_PENDING_APPROVAL,
      SmartReturnConstants.APPROVAL_CHT,
      SmartReturnConstants.SOURCE_APP,
      approver.Id,
      'REJECT'
    );

    List<ApprovalActionResult> results;

    System.runAs(approver) {
      Test.startTest();

      results = ApprovalController.bulkReject(
        new List<Id>{ requestRecord.Id },
        'REQUEST_NOT_ELIGIBLE',
        'Reviewed by assigned approver.'
      );

      Test.stopTest();
    }

    Map<Id, ApprovalActionResult> resultById = resultsByRequestId(results);

    System.assertEquals(
      true,
      resultById.get(requestRecord.Id).success,
      'Reject failed: ' + resultById.get(requestRecord.Id).message
    );

    Return_Request__c actualRequest = [
      SELECT Status__c, Rejection_Reason__c, Internal_Notes__c
      FROM Return_Request__c
      WHERE Id = :requestRecord.Id
    ];

    System.assertEquals(
      SmartReturnConstants.STATUS_REJECTED,
      actualRequest.Status__c
    );

    System.assertEquals(
      'REQUEST_NOT_ELIGIBLE',
      actualRequest.Rejection_Reason__c
    );

    System.assertEquals(
      'Reviewed by assigned approver.',
      actualRequest.Internal_Notes__c
    );
  }

  @IsTest
  static void reject_ShouldRequireReason() {
    Boolean exceptionThrown = false;

    Test.startTest();

    try {
      ApprovalController.bulkReject(
        new List<Id>{ UserInfo.getUserId() },
        ' ',
        null
      );
    } catch (AuraHandledException ex) {
      exceptionThrown = true;
    }

    Test.stopTest();

    System.assertEquals(true, exceptionThrown);
  }

  //===================================================
  // Risk routing
  //===================================================
  @IsTest
  static void approvalRouting_ShouldCountCurrentRequestForRisk() {
    Account customer = createCustomer('RISK');

    Integer threshold = SmartReturnConfigService.getRiskRequestCount();

    for (Integer index = 0; index < threshold - 1; index++) {
      createRequest(
        customer.Id,
        SmartReturnConstants.STATUS_COMPLETED,
        SmartReturnConstants.APPROVAL_CHT,
        SmartReturnConstants.SOURCE_APP,
        100000,
        null,
        null,
        null,
        'RISK-' + index
      );
    }

    Return_Request__c currentRequest = createRequest(
      customer.Id,
      SmartReturnConstants.STATUS_NEW,
      null,
      SmartReturnConstants.SOURCE_APP,
      100000,
      null,
      null,
      null,
      'RISK-CURRENT'
    );

    Test.startTest();

    ApprovalRoutingService.evaluateInitialStatus(currentRequest);

    Test.stopTest();

    Return_Request__c actualRequest = [
      SELECT Status__c, Required_Approval_Level__c
      FROM Return_Request__c
      WHERE Id = :currentRequest.Id
    ];

    System.assertEquals(
      SmartReturnConstants.STATUS_PENDING_APPROVAL,
      actualRequest.Status__c
    );

    System.assertEquals(
      SmartReturnConstants.APPROVAL_QLV,
      actualRequest.Required_Approval_Level__c,
      'Request hiện tại phải được tính vào risk threshold.'
    );
  }

  //===================================================
  // Escalation batch
  //===================================================
  @IsTest
  static void escalationBatch_ShouldAssignRegionalManager() {
    User approver = getApprover();

    User regionalManager = createAdditionalUser('region');

    Account customer = createCustomer('ESCALATE');

    Return_Request__c requestRecord = createRequest(
      customer.Id,
      SmartReturnConstants.STATUS_PENDING_APPROVAL,
      SmartReturnConstants.APPROVAL_CHT,
      SmartReturnConstants.SOURCE_APP,
      5000000,
      approver.Id,
      System.now().addHours(-1),
      regionalManager.Id,
      'ESCALATE'
    );

    Return_Request__c beforeBatch = [
      SELECT
        Status__c,
        Required_Approval_Level__c,
        ApproverId__c,
        Approval_Due_At__c,
        Store__r.Region_Manager__c
      FROM Return_Request__c
      WHERE Id = :requestRecord.Id
    ];

    System.assertEquals(
      SmartReturnConstants.APPROVAL_CHT,
      beforeBatch.Required_Approval_Level__c
    );

    System.assertEquals(
      regionalManager.Id,
      beforeBatch.Store__r.Region_Manager__c
    );

    System.assert(
      beforeBatch.Approval_Due_At__c <= System.now(),
      'Fixture phải là request quá hạn.'
    );

    Test.startTest();

    Database.executeBatch(new ApprovalEscalationBatch(), 200);

    Test.stopTest();

    Return_Request__c actualRequest = [
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
      actualRequest.Status__c,
      'Escalation không được đổi status.'
    );

    System.assertEquals(
      SmartReturnConstants.APPROVAL_QLV,
      actualRequest.Required_Approval_Level__c
    );

    System.assertEquals(regionalManager.Id, actualRequest.ApproverId__c);

    /*
     * Không assert deadline null vì BRD chỉ yêu cầu
     * escalate CHT -> QLV. Nếu team chốt phải xóa deadline,
     * bổ sung assertion sau khi automation không reset field.
     */
  }

  @IsTest
  static void escalationBatch_ShouldIgnoreRecentChtRequest() {
    User approver = getApprover();

    User regionalManager = createAdditionalUser('recentregion');

    Account customer = createCustomer('RECENT');

    Return_Request__c requestRecord = createRequest(
      customer.Id,
      SmartReturnConstants.STATUS_PENDING_APPROVAL,
      SmartReturnConstants.APPROVAL_CHT,
      SmartReturnConstants.SOURCE_APP,
      5000000,
      approver.Id,
      System.now().addHours(24),
      regionalManager.Id,
      'RECENT'
    );

    Test.startTest();

    Database.executeBatch(new ApprovalEscalationBatch(), 200);

    Test.stopTest();

    Return_Request__c actualRequest = [
      SELECT Required_Approval_Level__c, ApproverId__c
      FROM Return_Request__c
      WHERE Id = :requestRecord.Id
    ];

    System.assertEquals(
      SmartReturnConstants.APPROVAL_CHT,
      actualRequest.Required_Approval_Level__c
    );

    System.assertEquals(approver.Id, actualRequest.ApproverId__c);
  }

  @IsTest
  static void escalationBatch_ShouldIgnoreExistingQlvRequest() {
    User approver = getApprover();

    User regionalManager = createAdditionalUser('qlvregion');

    Account customer = createCustomer('QLV');

    Return_Request__c requestRecord = createRequest(
      customer.Id,
      SmartReturnConstants.STATUS_PENDING_APPROVAL,
      SmartReturnConstants.APPROVAL_QLV,
      SmartReturnConstants.SOURCE_APP,
      30000000,
      regionalManager.Id,
      System.now().addHours(-1),
      regionalManager.Id,
      'QLV'
    );

    Test.startTest();

    Database.executeBatch(new ApprovalEscalationBatch(), 200);

    Test.stopTest();

    Return_Request__c actualRequest = [
      SELECT Required_Approval_Level__c, ApproverId__c
      FROM Return_Request__c
      WHERE Id = :requestRecord.Id
    ];

    System.assertEquals(
      SmartReturnConstants.APPROVAL_QLV,
      actualRequest.Required_Approval_Level__c
    );

    System.assertEquals(regionalManager.Id, actualRequest.ApproverId__c);
  }

  //===================================================
  // Controller validation
  //===================================================
  @IsTest
  static void controller_ShouldRejectEmptyRequestIds() {
    Boolean exceptionThrown = false;

    Test.startTest();

    try {
      ApprovalController.bulkApprove(new List<Id>());
    } catch (AuraHandledException ex) {
      exceptionThrown = true;
    }

    Test.stopTest();

    System.assertEquals(true, exceptionThrown);
  }

  @IsTest
  static void controller_ShouldRejectDuplicateRequestIds() {
    Account customer = createCustomer('DUPLICATE');

    Return_Request__c requestRecord = createRequest(
      customer.Id,
      SmartReturnConstants.STATUS_NEW,
      null,
      SmartReturnConstants.SOURCE_APP,
      100000,
      null,
      null,
      null,
      'DUPLICATE'
    );

    Boolean exceptionThrown = false;

    Test.startTest();

    try {
      ApprovalController.bulkApprove(
        new List<Id>{ requestRecord.Id, requestRecord.Id }
      );
    } catch (AuraHandledException ex) {
      exceptionThrown = true;
    }

    Test.stopTest();

    System.assertEquals(true, exceptionThrown);
  }
}
