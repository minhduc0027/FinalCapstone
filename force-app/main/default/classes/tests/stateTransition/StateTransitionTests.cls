@isTest
private class StateTransitionTests {
  @testSetup
  static void setupData() {
    List<Return_Request__c> requests = new List<Return_Request__c>{
      new Return_Request__c(Status__c = 'New'),
      new Return_Request__c(Status__c = 'New'),
      new Return_Request__c(Status__c = 'New')
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
      StateTransitionValidator.validate('New', '');
    } catch (StateTransitionValidator.StateTransitionException e) {
      exceptionCaught = true;
    }
    System.assert(exceptionCaught, 'Phải bắt được lỗi khi newStatus trống');

    // Trạng thái cũ và mới trùng nhau (giữ nguyên)
    StateTransitionValidator.validate('New', 'New');
    System.assert(StateTransitionValidator.isAllowed('New', 'New'));

    // Kiểm tra Terminal Status (trạng thái kết thúc)
    System.assert(StateTransitionValidator.isTerminal('Completed'));
    System.assert(StateTransitionValidator.isTerminal('Rejected'));
    System.assert(StateTransitionValidator.isTerminal('Cancelled'));
    System.assert(!StateTransitionValidator.isTerminal('New'));

    // Kiểm tra chuyển từ trạng thái kết thúc sang trạng thái khác (phải lỗi)
    exceptionCaught = false;
    try {
      StateTransitionValidator.validate('Completed', 'New');
    } catch (StateTransitionValidator.StateTransitionException e) {
      exceptionCaught = true;
    }
    System.assert(exceptionCaught, 'Không được phép chuyển từ Terminal status');

    // Kiểm tra chuyển đổi không được phép (ví dụ: New -> Completed)
    System.assert(!StateTransitionValidator.isAllowed('New', 'Completed'));
    exceptionCaught = false;
    try {
      StateTransitionValidator.validate('New', 'Completed');
    } catch (StateTransitionValidator.StateTransitionException e) {
      exceptionCaught = true;
    }
    System.assert(exceptionCaught, 'Phải chặn chuyển đổi không hợp lệ');

    // Kiểm tra chuyển đổi hợp lệ
    System.assert(
      StateTransitionValidator.isAllowed('New', 'Pending Approval')
    );
    StateTransitionValidator.validate('New', 'Pending Approval');

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
      StateTransitionService.transition(null, 'Pending Approval');
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
      StateTransitionService.transition(fakeId, 'Pending Approval');
    } catch (Exception e) {
      exceptionCaught = true;
    }
    System.assert(exceptionCaught);

    // Trường hợp targetStatus trùng với status hiện tại (return sớm)
    StateTransitionService.transition(req.Id, 'New');

    // Chuyển trạng thái hợp lệ thành công
    StateTransitionService.transition(req.Id, 'Pending Approval');
    Return_Request__c updatedReq = [
      SELECT Status__c
      FROM Return_Request__c
      WHERE Id = :req.Id
    ];
    System.assertEquals('Pending Approval', updatedReq.Status__c);

    // Chuyển trạng thái lỗi qua Service
    exceptionCaught = false;
    try {
      StateTransitionService.transition(req.Id, 'Completed');
    } catch (StateTransitionService.StateTransitionException e) {
      exceptionCaught = true;
    }
    System.assert(exceptionCaught);

    Test.stopTest();
  }
}
