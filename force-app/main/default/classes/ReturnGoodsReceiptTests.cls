@IsTest
private class ReturnGoodsReceiptTests {
  @TestSetup
  static void setup() {
    ReturnRequestTestDataFactory.createStoreOperator();
  }

  private static User actor() {
    return [SELECT Id FROM User WHERE Alias = 'rrstore' LIMIT 1];
  }

  private static Return_Request__c request(Id managerId, String status) {
    Return_Request__c row = ReturnRequestTestDataFactory.requests(
      1,
      null,
      managerId,
      UserInfo.getUserId()
    )[0];
    row.Status__c = status;
    row.Required_Approval_Level__c = 'CHT';
    insert as system row;
    return [
      SELECT Id, Status__c, LastModifiedDate
      FROM Return_Request__c
      WHERE Id = :row.Id
    ];
  }

  @IsTest
  static void receivesGoodsWithoutDirectStateRefundOrTaskAccess() {
    User receiver = actor();
    Return_Request__c row = request(receiver.Id, 'AWAITING_GOODS');
    insert as system new Task(
      Subject = 'Restricted task',
      OwnerId = receiver.Id,
      Status = 'Not Started',
      Priority = 'Normal'
    );
    System.runAs(receiver) {
      Assert.isFalse(
        Refund_Transaction__c.SObjectType.getDescribe(
            SObjectDescribeOptions.DEFERRED
          )
          .isAccessible(),
        'Store users cannot read refund data.'
      );
      Assert.areEqual(
        0,
        [SELECT COUNT() FROM Task WITH USER_MODE],
        'Store users cannot read even their own tasks.'
      );
      Assert.isFalse(
        Return_Request__c.Status__c.getDescribe().isUpdateable(),
        'Workflow status cannot be edited directly.'
      );
      Test.startTest();
      ReturnRequestController.receiveGoods(row.Id, row.LastModifiedDate);
      Test.stopTest();
      Assert.areEqual(
        'INSPECTING',
        [SELECT Status__c FROM Return_Request__c WHERE Id = :row.Id].Status__c,
        'The controlled action receives goods.'
      );
    }
  }

  @IsTest
  static void rejectsDirectStatusUpdate() {
    User receiver = actor();
    Return_Request__c row = request(receiver.Id, 'AWAITING_GOODS');
    System.runAs(receiver) {
      Test.startTest();
      Database.SaveResult result = Database.update(
        new Return_Request__c(Id = row.Id, Status__c = 'CANCELLED'),
        false,
        AccessLevel.USER_MODE
      );
      Test.stopTest();
      Assert.isFalse(
        result.isSuccess(),
        'User-mode API updates must not edit status.'
      );
    }
    Assert.areEqual(
      'AWAITING_GOODS',
      [SELECT Status__c FROM Return_Request__c WHERE Id = :row.Id].Status__c,
      'The direct edit must not change the request.'
    );
  }

  @IsTest
  static void approvesThroughWorkspaceWithReadOnlyStatus() {
    User receiver = actor();
    Return_Request__c row = request(receiver.Id, 'PENDING_APPROVAL');
    System.runAs(receiver) {
      Assert.isFalse(
        Return_Request__c.Status__c.getDescribe().isUpdateable(),
        'Approval does not require direct state editing.'
      );
      Test.startTest();
      List<ApprovalActionResult> results = ApprovalController.bulkApprove(
        new List<Id>{ row.Id }
      );
      Test.stopTest();
      Assert.isTrue(
        results[0].success,
        'The assigned manager can approve through the workspace.'
      );
      Assert.areEqual(
        'INSPECTING',
        [SELECT Status__c FROM Return_Request__c WHERE Id = :row.Id].Status__c,
        'Store approvals follow the existing approval route.'
      );
    }
  }

  @IsTest
  static void rejectsOtherStatuses() {
    User receiver = actor();
    Return_Request__c row = request(receiver.Id, 'PENDING_APPROVAL');
    System.runAs(receiver) {
      Test.startTest();
      try {
        ReturnRequestLifecycleService.receiveGoods(
          row.Id,
          row.LastModifiedDate
        );
        Assert.fail('Approval is a separate workflow.');
      } catch (ReturnRequestLifecycleService.LifecycleException e) {
        Assert.areEqual(
          'Không thể chuyển yêu cầu từ PENDING_APPROVAL sang INSPECTING.',
          e.getMessage(),
          'Retain MSG-20.'
        );
      }
      Test.stopTest();
    }
  }

  @IsTest
  static void rejectsStaleRequest() {
    User receiver = actor();
    Return_Request__c row = request(receiver.Id, 'AWAITING_GOODS');
    System.runAs(receiver) {
      Test.startTest();
      try {
        ReturnRequestLifecycleService.receiveGoods(
          row.Id,
          row.LastModifiedDate.addSeconds(-1)
        );
        Assert.fail('A stale view cannot receive goods.');
      } catch (ReturnRequestLifecycleService.LifecycleException e) {
        Assert.isTrue(
          e.getMessage().contains('vừa được người khác cập nhật'),
          'Return MSG-13.'
        );
      }
      Test.stopTest();
    }
  }

  @IsTest
  static void rejectsAnotherStoreEvenWhenShared() {
    User receiver = actor();
    Return_Request__c row = request(UserInfo.getUserId(), 'AWAITING_GOODS');
    insert as system new Return_Request__Share(
      ParentId = row.Id,
      UserOrGroupId = receiver.Id,
      AccessLevel = 'Edit',
      RowCause = Schema.Return_Request__Share.RowCause.Manual
    );
    System.runAs(receiver) {
      Test.startTest();
      try {
        ReturnRequestLifecycleService.receiveGoods(
          row.Id,
          row.LastModifiedDate
        );
        Assert.fail(
          'A shared record is not necessarily in the receiver store.'
        );
      } catch (ReturnRequestLifecycleService.LifecycleException e) {
        Assert.isTrue(
          e.getMessage().contains('cửa hàng của bạn'),
          'Require store membership.'
        );
      }
      Test.stopTest();
    }
  }
}
