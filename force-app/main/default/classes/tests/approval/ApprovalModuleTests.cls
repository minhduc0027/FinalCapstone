@IsTest
public class ApprovalModuleTests {
  /*
   * Không dùng @TestSetup cho các test cần Test.setCreatedDate
   * với thời điểm riêng biệt. Factory nhỏ giúp từng test có
   * dữ liệu độc lập và dễ đọc.
   */
  private static Account createCustomer() {
    Account customer = new Account(Name = 'Approval Test Customer');

    insert customer;
    return customer;
  }

  private static Return_Request__c createRequest(
    Id customerId,
    String status,
    String approvalLevel,
    String sourceChannel,
    Decimal estimatedRefund
  ) {
    Return_Request__c requestRecord = ReturnRequestTestDataFactory.requests(
      1,
      customerId
    )[0];
    requestRecord.Status__c = status;
    requestRecord.Required_Approval_Level__c = approvalLevel;
    requestRecord.Source_Channel__c = sourceChannel;
    requestRecord.Estimated_Refund_Amount__c = estimatedRefund;
    insert as system requestRecord;
    return requestRecord;
  }

  @IsTest
  static void batchEscalatesOverdueChtRequest() {
    Account customer = createCustomer();

    Return_Request__c overdueRequest = createRequest(
      customer.Id,
      SmartReturnConstants.STATUS_PENDING_APPROVAL,
      SmartReturnConstants.APPROVAL_CHT,
      SmartReturnConstants.SOURCE_APP,
      5000000
    );

    /*
     * Đặt CreatedDate đủ cũ để chắc chắn vượt mọi timeout
     * hợp lý đang cấu hình, ví dụ 24 giờ.
     */
    Test.setCreatedDate(overdueRequest.Id, System.now().addDays(-10));

    Test.startTest();

    Database.executeBatch(new ApprovalEscalationBatch(), 200);

    Test.stopTest();

    Return_Request__c actualRequest = [
      SELECT Status__c, Required_Approval_Level__c
      FROM Return_Request__c
      WHERE Id = :overdueRequest.Id
    ];

    System.assertEquals(
      SmartReturnConstants.STATUS_PENDING_APPROVAL,
      actualRequest.Status__c,
      'Escalation không được thay đổi status.'
    );

    System.assertEquals(
      SmartReturnConstants.APPROVAL_QLV,
      actualRequest.Required_Approval_Level__c,
      'Request CHT quá hạn phải được escalate lên QLV.'
    );
  }

  @IsTest
  static void batchDoesNotEscalateRecentChtRequest() {
    Account customer = createCustomer();

    Return_Request__c recentRequest = createRequest(
      customer.Id,
      SmartReturnConstants.STATUS_PENDING_APPROVAL,
      SmartReturnConstants.APPROVAL_CHT,
      SmartReturnConstants.SOURCE_APP,
      5000000
    );

    /*
     * Không thay CreatedDate, đây là request mới.
     */

    Test.startTest();

    Database.executeBatch(new ApprovalEscalationBatch(), 200);

    Test.stopTest();

    Return_Request__c actualRequest = [
      SELECT Required_Approval_Level__c
      FROM Return_Request__c
      WHERE Id = :recentRequest.Id
    ];

    System.assertEquals(
      SmartReturnConstants.APPROVAL_CHT,
      actualRequest.Required_Approval_Level__c,
      'Request chưa quá hạn phải tiếp tục chờ CHT.'
    );
  }

  @IsTest
  static void batchDoesNotEscalateExistingQlvRequest() {
    Account customer = createCustomer();

    Return_Request__c qlvRequest = createRequest(
      customer.Id,
      SmartReturnConstants.STATUS_PENDING_APPROVAL,
      SmartReturnConstants.APPROVAL_QLV,
      SmartReturnConstants.SOURCE_APP,
      30000000
    );

    Test.setCreatedDate(qlvRequest.Id, System.now().addDays(-10));

    Test.startTest();

    Database.executeBatch(new ApprovalEscalationBatch(), 200);

    Test.stopTest();

    Return_Request__c actualRequest = [
      SELECT Required_Approval_Level__c
      FROM Return_Request__c
      WHERE Id = :qlvRequest.Id
    ];

    System.assertEquals(
      SmartReturnConstants.APPROVAL_QLV,
      actualRequest.Required_Approval_Level__c,
      'Request đã ở mức QLV không được xử lý lại.'
    );
  }

  @IsTest
  static void schedulerEnqueuesEscalationBatch() {
    Test.startTest();

    String scheduledJobId = System.schedule(
      'Approval Escalation Test',
      '0 0 1 1 1 ? 2099',
      new ApprovalEscalationBatchScheduler()
    );

    Test.stopTest();

    CronTrigger scheduledJob = [
      SELECT Id, CronJobDetail.Name, State, TimesTriggered
      FROM CronTrigger
      WHERE Id = :scheduledJobId
    ];

    System.assertEquals(
      'Approval Escalation Test',
      scheduledJob.CronJobDetail.Name
    );
    List<AsyncApexJob> batchJobs = [
      SELECT Id, JobType, ApexClass.Name, Status
      FROM AsyncApexJob
      WHERE ApexClass.Name = 'ApprovalEscalationBatch'
    ];

    System.assert(
      !batchJobs.isEmpty(),
      'Scheduler phải enqueue ApprovalEscalationBatch.'
    );
  }

  @IsTest
  static void approveAppRequestMovesToAwaitingGoods() {
    Account customer = createCustomer();

    Return_Request__c requestRecord = createRequest(
      customer.Id,
      SmartReturnConstants.STATUS_PENDING_APPROVAL,
      SmartReturnConstants.APPROVAL_CHT,
      SmartReturnConstants.SOURCE_APP,
      5000000
    );

    Test.startTest();

    ApprovalService.approveRequest(
      String.valueOf(requestRecord.Id),
      SmartReturnConstants.SOURCE_APP
    );

    Test.stopTest();

    Return_Request__c actualRequest = [
      SELECT Status__c
      FROM Return_Request__c
      WHERE Id = :requestRecord.Id
    ];

    System.assertEquals(
      SmartReturnConstants.STATUS_AWAITING_GOODS,
      actualRequest.Status__c,
      'APP request sau khi approve phải chờ khách mang hàng.'
    );
  }

  @IsTest
  static void approvePosRequestMovesToInspecting() {
    Account customer = createCustomer();

    Return_Request__c requestRecord = createRequest(
      customer.Id,
      SmartReturnConstants.STATUS_PENDING_APPROVAL,
      SmartReturnConstants.APPROVAL_CHT,
      SmartReturnConstants.SOURCE_POS,
      5000000
    );

    Test.startTest();

    ApprovalService.approveRequest(
      String.valueOf(requestRecord.Id),
      SmartReturnConstants.SOURCE_POS
    );

    Test.stopTest();

    Return_Request__c actualRequest = [
      SELECT Status__c
      FROM Return_Request__c
      WHERE Id = :requestRecord.Id
    ];

    System.assertEquals(
      SmartReturnConstants.STATUS_INSPECTING,
      actualRequest.Status__c,
      'Request không phải APP phải chuyển sang INSPECTING.'
    );
  }

  @IsTest
  static void approveBulkPosRequestMovesToInspecting() {
    Account customer = createCustomer();

    Return_Request__c requestRecord = createRequest(
      customer.Id,
      SmartReturnConstants.STATUS_PENDING_APPROVAL,
      SmartReturnConstants.APPROVAL_CHT,
      SmartReturnConstants.SOURCE_POS,
      5000000
    );
    Return_Request__c requestRecord2 = createRequest(
      customer.Id,
      SmartReturnConstants.STATUS_PENDING_APPROVAL,
      SmartReturnConstants.APPROVAL_CHT,
      SmartReturnConstants.SOURCE_POS,
      4000000
    );
    List<Id> requestIds = new List<Id>{ requestRecord.Id, requestRecord2.Id };
    Test.startTest();

    ApprovalService.approveRequestBulk(
      requestIds,
      SmartReturnConstants.SOURCE_POS
    );

    Test.stopTest();

    List<Return_Request__c> actualRequests = [
      SELECT Status__c
      FROM Return_Request__c
      WHERE Id IN :requestIds
    ];

    for (Return_Request__c request : actualRequests) {
      System.assertEquals(
        SmartReturnConstants.STATUS_INSPECTING,
        request.Status__c,
        'Request không phải APP phải chuyển sang INSPECTING.'
      );
    }
  }

  @IsTest
  static void rejectRequestMovesToRejected() {
    Account customer = createCustomer();

    Return_Request__c requestRecord = createRequest(
      customer.Id,
      SmartReturnConstants.STATUS_PENDING_APPROVAL,
      SmartReturnConstants.APPROVAL_CHT,
      SmartReturnConstants.SOURCE_APP,
      5000000
    );

    Test.startTest();

    ApprovalService.rejectRequest(
      String.valueOf(requestRecord.Id),
      'Return request does not meet approval conditions.'
    );

    Test.stopTest();

    Return_Request__c actualRequest = [
      SELECT Status__c, Rejection_Reason__c
      FROM Return_Request__c
      WHERE Id = :requestRecord.Id
      WITH SYSTEM_MODE
    ];

    System.assertEquals(
      SmartReturnConstants.STATUS_REJECTED,
      actualRequest.Status__c,
      'Reject request phải chuyển trạng thái sang REJECTED.'
    );
    Assert.areEqual(
      'Return request does not meet approval conditions.',
      actualRequest.Rejection_Reason__c,
      'Rejecting a request must persist the supplied reason.'
    );
  }

  @IsTest
  static void rejectRequestRequiresReason() {
    Account customer = createCustomer();

    Return_Request__c requestRecord = createRequest(
      customer.Id,
      SmartReturnConstants.STATUS_PENDING_APPROVAL,
      SmartReturnConstants.APPROVAL_CHT,
      SmartReturnConstants.SOURCE_APP,
      5000000
    );

    Boolean exceptionThrown = false;

    Test.startTest();

    try {
      ApprovalService.rejectRequest(String.valueOf(requestRecord.Id), ' ');
    } catch (StateTransitionService.StateTransitionException ex) {
      exceptionThrown = true;

      System.assertEquals('Rejection reason cannot be blank.', ex.getMessage());
    }

    Test.stopTest();

    System.assertEquals(true, exceptionThrown, 'Reason trống phải bị chặn.');

    Return_Request__c actualRequest = [
      SELECT Status__c
      FROM Return_Request__c
      WHERE Id = :requestRecord.Id
    ];

    System.assertEquals(
      SmartReturnConstants.STATUS_PENDING_APPROVAL,
      actualRequest.Status__c,
      'Request không được thay đổi khi reason không hợp lệ.'
    );
  }

  @IsTest
  static void initialRoutingSendsHighAmountToPendingApproval() {
    Account customer = createCustomer();

    /*
     * Giá trị lớn để chắc chắn vượt Auto Approval Limit.
     * Điều này giúp test không phụ thuộc trạng thái feature flag.
     */
    Return_Request__c requestRecord = createRequest(
      customer.Id,
      SmartReturnConstants.STATUS_NEW,
      null,
      SmartReturnConstants.SOURCE_APP,
      999999999
    );

    Test.startTest();

    ApprovalRoutingService.evaluateInitialStatus(requestRecord);

    Test.stopTest();

    Return_Request__c actualRequest = [
      SELECT Status__c
      FROM Return_Request__c
      WHERE Id = :requestRecord.Id
    ];

    System.assertEquals(
      SmartReturnConstants.STATUS_PENDING_APPROVAL,
      actualRequest.Status__c,
      'Request vượt auto limit phải chờ manual approval.'
    );
  }

  @IsTest
  static void initialRoutingSendsHighAmountToPendingApproval_CHT() {
    Account customer = createCustomer();

    /*
     * Giá trị lớn để chắc chắn vượt Auto Approval Limit.
     * Điều này giúp test không phụ thuộc trạng thái feature flag.
     */
    Decimal storeApprovalLimit = SmartReturnConfigService.getStoreApprovalLimit();
    Return_Request__c requestRecord = createRequest(
      customer.Id,
      SmartReturnConstants.STATUS_NEW,
      null,
      SmartReturnConstants.SOURCE_APP,
      storeApprovalLimit
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
      actualRequest.Status__c,
      'Request vượt auto limit phải chờ manual approval.'
    );
    System.assertEquals(
      SmartReturnConstants.APPROVAL_CHT,
      actualRequest.Required_Approval_Level__c,
      'Request vượt auto limit phải chờ manual approval.'
    );
  }
}
