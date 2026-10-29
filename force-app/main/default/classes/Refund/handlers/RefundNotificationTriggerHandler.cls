public inherited sharing class RefundNotificationTriggerHandler {
  public static void dispatch() {
    switch on Trigger.operationType {
      when AFTER_INSERT {
        RefundService.notifyStoreManagers(
          (List<Refund_Notification__e>) Trigger.new
        );
      }
    }
  }
}
