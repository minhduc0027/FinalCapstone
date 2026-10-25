@isTest
private class StateTransitionTests {
  @testSetup
  static void setupData() {
    List<Return_Request__c> requests = new List<Return_Request__c>{
      new Return_Request__c(Status__c = SmartReturnConstants.STATUS_NEW),
      new Return_Request__c(Status__c = SmartReturnConstants.STATUS_NEW),
      new Return_Request__c(Status__c = SmartReturnConstants.STATUS_NEW)
    };
    insert requests;
  }

  // ==========================================
  // 1. TEST STATE TRANSITION VALIDATOR
  // ==========================================
  @isTest
  static void testValidatorScenarios() {
    Test.startTest();

    // Kiểm tra trạng thái cũ hoặc mới bị trống (Blank)
    Boolean exceptionCaught = false;
    try {
      StateTransitionValidator.validate(
        null,
        SmartReturnConstants.STATUS_PENDING_APPROVAL
      );
    } catch (StateTransitionValidator.StateTransitionException e) {
      exceptionCaught = true;
    }
    System.assert(exceptionCaught, 'Phải bắt được lỗi khi oldStatus trống');

    exceptionCaught = false;
    try {
      StateTransitionValidator.validate(SmartReturnConstants.STATUS_NEW, null);
    } catch (StateTransitionValidator.StateTransitionException e) {
      exceptionCaught = true;
    }
    System.assert(exceptionCaught, 'Phải bắt được lỗi khi newStatus trống');

    // Trạng thái cũ và mới trùng nhau (giữ nguyên)
    StateTransitionValidator.validate(
      SmartReturnConstants.STATUS_NEW,
      SmartReturnConstants.STATUS_NEW
    );
    System.assert(
      StateTransitionValidator.isAllowed(
        SmartReturnConstants.STATUS_NEW,
        SmartReturnConstants.STATUS_NEW
      )
    );

    // Kiểm tra Terminal Status (trạng thái kết thúc)
    System.assert(
      StateTransitionValidator.isTerminal(SmartReturnConstants.STATUS_COMPLETED)
    );
    System.assert(
      StateTransitionValidator.isTerminal(SmartReturnConstants.STATUS_REJECTED)
    );
    System.assert(
      StateTransitionValidator.isTerminal(SmartReturnConstants.STATUS_CANCELLED)
    );
    System.assert(
      !StateTransitionValidator.isTerminal(SmartReturnConstants.STATUS_NEW)
    );

    // Kiểm tra chuyển từ trạng thái kết thúc sang trạng thái khác (phải lỗi)
    exceptionCaught = false;
    try {
      StateTransitionValidator.validate(
        SmartReturnConstants.STATUS_COMPLETED,
        SmartReturnConstants.STATUS_NEW
      );
    } catch (StateTransitionValidator.StateTransitionException e) {
      exceptionCaught = true;
    }
    System.assert(exceptionCaught, 'Không được phép chuyển từ Terminal status');

    // Kiểm tra chuyển đổi không được phép (ví dụ: NEW -> COMPLETED)
    System.assert(
      !StateTransitionValidator.isAllowed(
        SmartReturnConstants.STATUS_NEW,
        SmartReturnConstants.STATUS_COMPLETED
      )
    );
    exceptionCaught = false;
    try {
      StateTransitionValidator.validate(
        SmartReturnConstants.STATUS_NEW,
        SmartReturnConstants.STATUS_COMPLETED
      );
    } catch (StateTransitionValidator.StateTransitionException e) {
      exceptionCaught = true;
    }
    System.assert(exceptionCaught, 'Phải chặn chuyển đổi không hợp lệ');

    // Kiểm tra chuyển đổi hợp lệ
    System.assert(
      StateTransitionValidator.isAllowed(
        SmartReturnConstants.STATUS_NEW,
        SmartReturnConstants.STATUS_PENDING_APPROVAL
      )
    );
    StateTransitionValidator.validate(
      SmartReturnConstants.STATUS_NEW,
      SmartReturnConstants.STATUS_PENDING_APPROVAL
    );

    Test.stopTest();
  }

  @IsTest
  static void triggerRoutesStatusValidationToStateTransitionService() {
    List<Return_Request__c> requests = [
      SELECT Id, Status__c
      FROM Return_Request__c
      ORDER BY Id
      LIMIT 2
    ];
    requests[0].Status__c = SmartReturnConstants.STATUS_PENDING_APPROVAL;
    requests[1].Status__c = SmartReturnConstants.STATUS_COMPLETED;

    Test.startTest();
    Database.SaveResult[] results = Database.update(requests, false);
    Test.stopTest();

    Assert.isTrue(results[0].isSuccess(), 'The valid transition must save.');
    Assert.isFalse(
      results[1].isSuccess(),
      'The invalid transition must be rejected.'
    );
    Assert.isTrue(
      results[1].getErrors()[0].getMessage().contains('Không thể chuyển'),
      'The status validator must explain the rejected transition.'
    );
  }

  // ==========================================
  // 2. TEST STATE TRANSITION SERVICE (SINGLE)
  // ==========================================
  @isTest
  static void testServiceSingleTransition() {
    Return_Request__c req = [
      SELECT Id, Status__c
      FROM Return_Request__c
      LIMIT 1
    ];

    Test.startTest();

    // Trường hợp requestId = null
    Boolean exceptionCaught = false;
    try {
      StateTransitionService.transition(
        null,
        SmartReturnConstants.STATUS_PENDING_APPROVAL,
        null
      );
    } catch (StateTransitionService.StateTransitionException e) {
      exceptionCaught = true;
    }
    System.assert(exceptionCaught);
    // Trường hợp targetStatus trùng với status hiện tại (return sớm)
    StateTransitionService.transition(
      req.Id,
      SmartReturnConstants.STATUS_NEW,
      null
    );
    // Chuyển trạng thái hợp lệ thành công
    StateTransitionService.transition(
      req.Id,
      SmartReturnConstants.STATUS_PENDING_APPROVAL,
      SmartReturnConstants.APPROVAL_AUTO
    );
    Return_Request__c updatedReq = [
      SELECT Status__c
      FROM Return_Request__c
      WHERE Id = :req.Id
    ];
    System.assertEquals(
      SmartReturnConstants.STATUS_PENDING_APPROVAL,
      updatedReq.Status__c
    );
    Test.stopTest();
  }

  @IsTest
  static void transitionBulk_ShouldUpdateMultipleRecords() {
    List<Return_Request__c> requests = new List<Return_Request__c>();

    for (Integer i = 0; i < 2; i++) {
      requests.add(
        new Return_Request__c(
          Status__c = SmartReturnConstants.STATUS_NEW,
          Source_Channel__c = 'STORE'
        )
      );
    }

    insert requests;

    List<TransitionRequest> transitionRequests = new List<TransitionRequest>();

    for (Return_Request__c request : requests) {
      transitionRequests.add(
        new TransitionRequest(
          request.Id,
          SmartReturnConstants.STATUS_PENDING_APPROVAL,
          SmartReturnConstants.APPROVAL_CHT
        )
      );
    }

    Test.startTest();

    List<TransitionResult> results = StateTransitionService.transitionBulk(
      transitionRequests
    );

    Test.stopTest();

    System.assertEquals(2, results.size());

    List<Return_Request__c> updatedRequests = [
      SELECT Status__c, Required_Approval_Level__c
      FROM Return_Request__c
      WHERE Id IN :requests
    ];

    for (Return_Request__c request : updatedRequests) {
      System.assertEquals(
        SmartReturnConstants.STATUS_PENDING_APPROVAL,
        request.Status__c
      );

      System.assertEquals(
        SmartReturnConstants.APPROVAL_CHT,
        request.Required_Approval_Level__c
      );
    }
  }

  @IsTest
  static void transitionBulkAllOrNoneUpdatesEveryRequest() {
    List<Return_Request__c> requests = [
      SELECT Id, Status__c
      FROM Return_Request__c
      ORDER BY Id
      LIMIT 2
    ];
    List<TransitionRequest> changes = new List<TransitionRequest>();
    for (Return_Request__c request : requests) {
      changes.add(
        new TransitionRequest(
          request.Id,
          SmartReturnConstants.STATUS_PENDING_APPROVAL,
          null
        )
      );
    }

    Test.startTest();
    List<TransitionResult> results = StateTransitionService.transitionBulk(
      changes,
      true
    );
    Test.stopTest();

    Assert.areEqual(2, results.size(), 'Every transition must report success.');
    String expectedStatus = SmartReturnConstants.STATUS_PENDING_APPROVAL;
    Assert.areEqual(
      2,
      [
        SELECT COUNT()
        FROM Return_Request__c
        WHERE Id IN :requests AND Status__c = :expectedStatus
      ],
      'Every valid request must transition.'
    );
  }

  @IsTest
  static void transitionBulkAllOrNoneRejectsEntireInvalidGroup() {
    List<Return_Request__c> requests = [
      SELECT Id, Status__c
      FROM Return_Request__c
      ORDER BY Id
      LIMIT 2
    ];
    List<TransitionRequest> changes = new List<TransitionRequest>{
      new TransitionRequest(
        requests[0].Id,
        SmartReturnConstants.STATUS_PENDING_APPROVAL,
        null
      ),
      new TransitionRequest(
        requests[1].Id,
        SmartReturnConstants.STATUS_COMPLETED,
        null
      )
    };

    Test.startTest();
    try {
      StateTransitionService.transitionBulk(changes, true);
      Assert.fail('An invalid transition must reject the entire group.');
    } catch (StateTransitionValidator.StateTransitionException e) {
      Assert.isTrue(
        e.getMessage().contains('Không thể chuyển'),
        'Explain the invalid transition.'
      );
    }
    Test.stopTest();

    String originalStatus = SmartReturnConstants.STATUS_NEW;
    Assert.areEqual(
      2,
      [
        SELECT COUNT()
        FROM Return_Request__c
        WHERE Id IN :requests AND Status__c = :originalStatus
      ],
      'No request may transition when another is invalid.'
    );
  }

  @IsTest
  static void transitionBulkAllOrNoneRejectsDuplicateRequest() {
    Id requestId = [SELECT Id FROM Return_Request__c LIMIT 1].Id;
    List<TransitionRequest> changes = new List<TransitionRequest>{
      new TransitionRequest(
        requestId,
        SmartReturnConstants.STATUS_PENDING_APPROVAL,
        null
      ),
      new TransitionRequest(
        requestId,
        SmartReturnConstants.STATUS_PENDING_APPROVAL,
        null
      )
    };

    Test.startTest();
    try {
      StateTransitionService.transitionBulk(changes, true);
      Assert.fail('Duplicate request IDs must not be updated twice.');
    } catch (StateTransitionService.StateTransitionException e) {
      Assert.isTrue(
        e.getMessage().contains('unique Id'),
        'Explain duplicate request IDs.'
      );
    }
    Test.stopTest();

    Assert.areEqual(
      SmartReturnConstants.STATUS_NEW,
      [SELECT Status__c FROM Return_Request__c WHERE Id = :requestId].Status__c,
      'A duplicate input must leave the request unchanged.'
    );
  }

  @IsTest
  static void transitionBulkAllOrNoneRejectsMissingRequest() {
    List<TransitionRequest> changes = new List<TransitionRequest>{
      new TransitionRequest(
        UserInfo.getUserId(),
        SmartReturnConstants.STATUS_PENDING_APPROVAL,
        null
      )
    };

    Test.startTest();
    try {
      StateTransitionService.transitionBulk(changes, true);
      Assert.fail('A missing request must stop the whole transition.');
    } catch (StateTransitionService.StateTransitionException e) {
      Assert.areEqual(
        'Request not found.',
        e.getMessage(),
        'Explain the missing request.'
      );
    }
    Test.stopTest();
  }
}
