trigger RefundNotificationTrigger on Refund_Notification__e(after insert) {
  RefundNotificationTriggerHandler.dispatch();
}
