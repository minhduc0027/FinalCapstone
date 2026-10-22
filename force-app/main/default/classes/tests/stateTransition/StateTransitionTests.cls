@isTest
private class StateTransitionTests {
  @testSetup
  static void setupData() {
    List<Return_Request__c> requests = new List<Return_Request__c>{
      new Return_Request__c(Status__c = 'NEW'),
      new Return_Request__c(Status__c = 'NEW'),
      new Return_Request__c(Status__c = 'NEW')
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
      StateTransitionValidator.validate(null, 'Pending Approval');
    } catch (StateTransitionValidator.StateTransitionException e) {
      exceptionCaught = true;
    }
    System.assert(exceptionCaught, 'Phải bắt được lỗi khi oldStatus trống');

    exceptionCaught = false;
    try {
      StateTransitionValidator.validate('NEW', '');
    } catch (StateTransitionValidator.StateTransitionException e) {
      exceptionCaught = true;
    }
    System.assert(exceptionCaught, 'Phải bắt được lỗi khi newStatus trống');

    // Trạng thái cũ và mới trùng nhau (giữ nguyên)
    StateTransitionValidator.validate('NEW', 'NEW');
    System.assert(StateTransitionValidator.isAllowed('NEW', 'NEW'));

    // Kiểm tra Terminal Status (trạng thái kết thúc)
    System.assert(StateTransitionValidator.isTerminal('COMPLETED'));
    System.assert(StateTransitionValidator.isTerminal('REJECTED'));
    System.assert(StateTransitionValidator.isTerminal('CANCELLED'));
    System.assert(!StateTransitionValidator.isTerminal('NEW'));

    // Kiểm tra chuyển từ trạng thái kết thúc sang trạng thái khác (phải lỗi)
    exceptionCaught = false;
    try {
      StateTransitionValidator.validate('COMPLETED', 'NEW');
    } catch (StateTransitionValidator.StateTransitionException e) {
      exceptionCaught = true;
    }
    System.assert(exceptionCaught, 'Không được phép chuyển từ Terminal status');

    // Kiểm tra chuyển đổi không được phép (ví dụ: NEW -> COMPLETED)
    System.assert(!StateTransitionValidator.isAllowed('NEW', 'COMPLETED'));
    exceptionCaught = false;
    try {
      StateTransitionValidator.validate('NEW', 'COMPLETED');
    } catch (StateTransitionValidator.StateTransitionException e) {
      exceptionCaught = true;
    }
    System.assert(exceptionCaught, 'Phải chặn chuyển đổi không hợp lệ');

    // Kiểm tra chuyển đổi hợp lệ
    System.assert(
      StateTransitionValidator.isAllowed('NEW', 'PENDING_APPROVAL')
    );
    StateTransitionValidator.validate('NEW', 'PENDING_APPROVAL');

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
      StateTransitionService.transition(null, 'PENDING_APPROVAL');
    } catch (StateTransitionService.StateTransitionException e) {
      exceptionCaught = true;
    }
    System.assert(exceptionCaught);

    // Trường hợp không tìm thấy Return Request (ID không tồn tại)
    Id fakeId =
      Return_Request__c.sObjectType.getDescribe().getKeyPrefix() +
      '0000000003ABC';
    exceptionCaught = false;
    try {
      StateTransitionService.transition(fakeId, 'PENDING_APPROVAL');
    } catch (Exception e) {
      exceptionCaught = true;
    }
    System.assert(exceptionCaught);

    // Trường hợp targetStatus trùng với status hiện tại (return sớm)
    StateTransitionService.transition(req.Id, 'NEW');

    // Chuyển trạng thái hợp lệ thành công
    StateTransitionService.transition(req.Id, 'PENDING_APPROVAL');
    Return_Request__c updatedReq = [
      SELECT Status__c
      FROM Return_Request__c
      WHERE Id = :req.Id
    ];
    System.assertEquals('PENDING_APPROVAL', updatedReq.Status__c);

    // Chuyển trạng thái lỗi qua Service
    exceptionCaught = false;
    try {
      StateTransitionService.transition(req.Id, 'COMPLETED');
    } catch (StateTransitionService.StateTransitionException e) {
      exceptionCaught = true;
    }
    System.assert(exceptionCaught);

    Test.stopTest();
  }
}
