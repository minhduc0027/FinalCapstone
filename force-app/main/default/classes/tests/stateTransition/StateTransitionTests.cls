@isTest
private class StateTransitionTests {
  @testSetup
  static void setupData() {
    List<Case> cases = new List<Case>{
      new Case(Status = 'New'),
      new Case(Status = 'New'),
      new Case(Status = 'New')
    };
    insert cases;
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
    Case c = [SELECT Id, Status FROM Case LIMIT 1];

    Test.startTest();

    // Trường hợp caseId = null
    Boolean exceptionCaught = false;
    try {
      StateTransitionService.transition(null, 'Pending Approval', 'Note');
    } catch (StateTransitionService.StateTransitionException e) {
      exceptionCaught = true;
    }
    System.assert(exceptionCaught);

    // Trường hợp không tìm thấy Case (ID không tồn tại)
    Id fakeId = Id.valueOf('500000000000000AAA');
    exceptionCaught = false;
    try {
      StateTransitionService.transition(fakeId, 'Pending Approval', 'Note');
    } catch (StateTransitionService.StateTransitionException e) {
      exceptionCaught = true;
    }
    System.assert(exceptionCaught);

    // Trường hợp targetStatus trùng với status hiện tại (return sớm)
    StateTransitionService.transition(c.Id, 'New', 'Same status note');

    // Chuyển trạng thái hợp lệ thành công
    StateTransitionService.transition(
      c.Id,
      'Pending Approval',
      'Approval note'
    );
    Case updatedCase = [SELECT Status FROM Case WHERE Id = :c.Id];
    System.assertEquals('Pending Approval', updatedCase.Status);

    // Chuyển trạng thái lỗi qua Service
    exceptionCaught = false;
    try {
      StateTransitionService.transition(c.Id, 'Completed', 'Invalid note');
    } catch (StateTransitionService.StateTransitionException e) {
      exceptionCaught = true;
    }
    System.assert(exceptionCaught);

    Test.stopTest();
  }

  // ==========================================
  // 3. TEST STATE TRANSITION SERVICE (BULK)
  // ==========================================
  @isTest
  static void testServiceBulkTransition() {
    List<Case> cases = [SELECT Id, Status FROM Case];

    Test.startTest();

    // Truyền tham số null hoặc empty collection
    System.assertEquals(0, StateTransitionService.transitionBulk(null).size());
    System.assertEquals(
      0,
      StateTransitionService.transitionBulk(
          new Map<Id, StateTransitionService.TransitionRequest>()
        )
        .size()
    );

    Map<Id, StateTransitionService.TransitionRequest> requests = new Map<Id, StateTransitionService.TransitionRequest>();

    // 1. Chuyển hợp lệ
    requests.put(
      cases[0].Id,
      new StateTransitionService.TransitionRequest(
        'Pending Approval',
        'Bulk note 1'
      )
    );

    // 2. Trùng trạng thái hiện tại
    requests.put(
      cases[1].Id,
      new StateTransitionService.TransitionRequest('New', 'Bulk note 2')
    );

    // 3. Chuyển không hợp lệ (New -> Completed)
    requests.put(
      cases[2].Id,
      new StateTransitionService.TransitionRequest('Completed', 'Bulk note 3')
    );

    List<StateTransitionService.TransitionResult> results = StateTransitionService.transitionBulk(
      requests
    );
    System.assert(!results.isEmpty());

    // Kiểm tra method lấy note (sau khi kết thúc transaction bulk, map bị clear)
    System.assertEquals(
      null,
      StateTransitionService.getTransitionNote(cases[0].Id)
    );

    Test.stopTest();
  }

  // ==========================================
  // 4. TEST TRIGGER HANDLER & DML VALIDATION
  // ==========================================
  @isTest
  static void testTriggerHandlerBranches() {
    Case c = [SELECT Id, Status FROM Case LIMIT 1];

    Test.startTest();

    // Nhánh 1: oldRecord == null (giả lập context thiếu bản ghi cũ)
    Case newRecordNullOld = new Case(Id = c.Id, Status = 'Pending Approval');
    ReturnRequestTriggerHandler.beforeUpdate(
      new List<Case>{ newRecordNullOld },
      new Map<Id, Case>()
    );

    // Nhánh 2: oldRecord.Status == newRecord.Status (không đổi trạng thái)
    Case oldRecSame = new Case(Id = c.Id, Status = 'New');
    Case newRecSame = new Case(Id = c.Id, Status = 'New');
    ReturnRequestTriggerHandler.beforeUpdate(
      new List<Case>{ newRecSame },
      new Map<Id, Case>{ c.Id => oldRecSame }
    );

    Test.stopTest();
  }

  @isTest
  static void testTriggerDmlError() {
    Case c = [SELECT Id, Status FROM Case LIMIT 1];

    // Cố tình update trực tiếp sai quy luật để trigger kích hoạt `addError`
    c.Status = 'Completed';

    Test.startTest();
    Boolean dmlExceptionCaught = false;
    try {
      update c;
    } catch (DmlException e) {
      dmlExceptionCaught = true;
    }
    System.assert(
      dmlExceptionCaught,
      'Trigger phải bắt lỗi và ném DmlException khi update sai trạng thái'
    );
    Test.stopTest();
  }
}
