@IsTest
private class RefundNotificationTest {
  @TestSetup
  static void setup() {
    User manager = RefundTestDataFactory.grantProcessor();
    System.runAs(new User(Id = UserInfo.getUserId())) {
      Return_Request__c request = RefundTestDataFactory.requests(
        1,
        'REFUND_PROCESSING',
        true,
        manager.Id
      )[0];
      update new Store__c(Id = request.Store__c, Store_Code__c = 'RF-NOTIFY');
    }
  }

  private static Return_Request__c requestWithManager() {
    Return_Request__c request = [
      SELECT Id, Store__c
      FROM Return_Request__c
      LIMIT 1
    ];
    return request;
  }

  private static Refund_Notification__e outcome(Id requestId, String status) {
    return new Refund_Notification__e(
      Request_Id__c = requestId,
      Outcome__c = status
    );
  }

  @IsTest
  static void sendsSuccessToStoreManager() {
    Return_Request__c request = requestWithManager();
    Return_Request__c routed = RefundNotificationSelector.requests(
        new Set<Id>{ request.Id }
      )
      .get(request.Id);
    Assert.areEqual(
      RefundTestDataFactory.processor().Id,
      routed.Store__r.Store_Manager__c,
      'Resolve the store manager even when another user owns the request.'
    );
    Test.startTest();
    RefundService.notifyStoreManagers(
      new List<Refund_Notification__e>{ outcome(request.Id, 'COMPLETED') }
    );
    Test.stopTest();
    Assert.areEqual(
      1,
      RefundService.notificationsSent,
      'Send a native notification for successful completion.'
    );
    Assert.areEqual(
      0,
      [SELECT COUNT() FROM Application_Log__c WHERE Level__c = 'ERROR'],
      'The notification API must accept the deployed type and target.'
    );
  }

  @IsTest
  static void sendsFinalFailure() {
    Return_Request__c request = requestWithManager();
    Test.startTest();
    RefundService.notifyStoreManagers(
      new List<Refund_Notification__e>{ outcome(request.Id, 'REFUND_FAILED') }
    );
    Test.stopTest();
    Assert.areEqual(
      1,
      RefundService.notificationsSent,
      'Send a native notification for final refund failure.'
    );
  }

  @IsTest
  static void skipsMissingManagerInsteadOfOwner() {
    Return_Request__c request = [
      SELECT Id, Store__c
      FROM Return_Request__c
      LIMIT 1
    ];
    update new Store__c(Id = request.Store__c, Store_Manager__c = null);
    Test.startTest();
    RefundService.notifyStoreManagers(
      new List<Refund_Notification__e>{ outcome(request.Id, 'COMPLETED') }
    );
    Test.stopTest();
    Assert.areEqual(
      0,
      RefundService.notificationsSent,
      'The request owner is not a substitute for its store manager.'
    );
    Assert.areEqual(
      1,
      [
        SELECT COUNT()
        FROM Application_Log__c
        WHERE Source__c = 'RefundService' AND Level__c = 'WARN'
      ],
      'Keep evidence of the missing recipient.'
    );
  }

  @IsTest
  static void ignoresPendingOutcome() {
    Return_Request__c request = requestWithManager();
    Test.startTest();
    RefundService.notifyStoreManagers(
      new List<Refund_Notification__e>{
        outcome(request.Id, 'REFUND_PROCESSING')
      }
    );
    Test.stopTest();
    Assert.areEqual(
      0,
      RefundService.notificationsSent,
      'A pending or retryable result is not final failure.'
    );
  }

  @IsTest
  static void coalescesDuplicateOutcomesInBatch() {
    Return_Request__c request = requestWithManager();
    Test.startTest();
    RefundService.notifyStoreManagers(
      new List<Refund_Notification__e>{
        outcome(request.Id, 'COMPLETED'),
        outcome(request.Id, 'COMPLETED')
      }
    );
    Test.stopTest();
    Assert.areEqual(
      1,
      RefundService.notificationsSent,
      'Deliver a repeated request/outcome pair only once per batch.'
    );
  }

  @IsTest
  static void deliversPublishedEventThroughSubscriber() {
    Return_Request__c request = requestWithManager();
    Test.startTest();
    RefundService.publishManagerNotifications(
      new List<Refund_Transaction__c>{
        new Refund_Transaction__c(Return_Request__c = request.Id)
      },
      'COMPLETED'
    );
    Test.getEventBus().deliver();
    Test.stopTest();
    Assert.areEqual(
      1,
      RefundService.notificationEventsQueued,
      'Internal publication does not depend on the POS/App switch.'
    );
    Assert.areEqual(
      1,
      RefundService.notificationsSent,
      'The event trigger must reach the native notification sender.'
    );
  }

  @IsTest
  static void handlesBulkOutcomes() {
    List<Return_Request__c> requests = RefundTestDataFactory.requests(
      251,
      'REFUND_PROCESSING',
      false,
      RefundTestDataFactory.processor().Id
    );
    List<Refund_Notification__e> events = new List<Refund_Notification__e>();
    for (Return_Request__c request : requests)
      events.add(outcome(request.Id, 'COMPLETED'));
    Test.startTest();
    RefundService.notifyStoreManagers(events);
    Integer queries = Limits.getQueries();
    Test.stopTest();
    Assert.areEqual(
      requests.size(),
      RefundService.notificationsSent,
      'Every request must notify its manager in a bulk result batch.'
    );
    Assert.areEqual(
      2,
      queries,
      'Resolve requests and notification type once per batch.'
    );
  }

  @IsTest
  static void acceptsEmptyEvents() {
    Test.startTest();
    RefundService.notifyStoreManagers(new List<Refund_Notification__e>());
    Test.stopTest();
    Assert.areEqual(0, RefundService.notificationsSent, 'Nothing to deliver.');
  }

  @IsTest
  static void acceptsNullEvents() {
    Test.startTest();
    RefundService.notifyStoreManagers(null);
    Test.stopTest();
    Assert.areEqual(0, RefundService.notificationsSent, 'Nothing to deliver.');
  }

  @IsTest
  static void callbackQueuesManagerNotificationRegardlessOfPosSwitch() {
    Return_Request__c request = requestWithManager();
    Refund_Transaction__c refund = RefundTestDataFactory.refund(
      request.Id,
      'PENDING'
    );
    System.runAs(RefundTestDataFactory.processor()) {
      Test.startTest();
      Integer status = RefundService.handleCallback(
        RefundTestDataFactory.callback(refund, 'SUCCESS')
      );
      Test.stopTest();
      Assert.areEqual(200, status, 'Persist the verified callback.');
      Assert.areEqual(
        1,
        RefundService.notificationEventsQueued,
        'Manager delivery must remain enabled independently of POS/App configuration.'
      );
    }
  }

  @IsTest
  static void skipsInactiveManager() {
    Return_Request__c request = requestWithManager();
    User manager = RefundTestDataFactory.processor();
    System.runAs(new User(Id = UserInfo.getUserId())) {
      manager.IsActive = false;
      update manager;
    }
    Test.startTest();
    RefundService.notifyStoreManagers(
      new List<Refund_Notification__e>{ outcome(request.Id, 'COMPLETED') }
    );
    Test.stopTest();
    Assert.areEqual(
      0,
      RefundService.notificationsSent,
      'Inactive managers must not receive notifications.'
    );
  }
}
