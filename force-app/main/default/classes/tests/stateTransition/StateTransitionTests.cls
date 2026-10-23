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
        SmartReturnConstants.STATUS_PENDINGS_APPROVAL
      )
    );
    StateTransitionValidator.validate(
      SmartReturnConstants.STATUS_NEW,
      SmartReturnConstants.STATUS_PENDING_APPROVAL
    );

    Test.stopTest();
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
}
