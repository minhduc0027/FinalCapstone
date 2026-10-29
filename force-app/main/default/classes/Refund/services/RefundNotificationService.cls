public with sharing class RefundNotificationService {
  @TestVisible
  private static Integer notificationsSent = 0;
  @TestVisible
  private static Integer eventsQueued = 0;

  public static void publish(
    List<Refund_Transaction__c> refunds,
    String outcome
  ) {
    List<Refund_Notification__e> events = new List<Refund_Notification__e>();
    for (Refund_Transaction__c refund : refunds) {
      events.add(
        new Refund_Notification__e(
          Request_Id__c = refund.Return_Request__c,
          Outcome__c = outcome
        )
      );
    }
    for (Database.SaveResult result : EventBus.publish(events)) {
      if (!result.isSuccess()) {
        throw new NotificationException(
          'Could not queue the store manager notification.'
        );
      }
    }
    eventsQueued += events.size();
  }

  public static void deliver(List<Refund_Notification__e> events) {
    if (events == null || events.isEmpty())
      return;

    Map<String, Refund_Notification__e> outcomes = new Map<String, Refund_Notification__e>();
    Set<Id> requestIds = new Set<Id>();
    for (Refund_Notification__e outcome : events) {
      if (
        outcome.Outcome__c != SmartReturnConstants.STATUS_COMPLETED &&
        outcome.Outcome__c != SmartReturnConstants.STATUS_REFUND_FAILED
      )
        continue;
      Id requestId = Id.valueOf(outcome.Request_Id__c);
      requestIds.add(requestId);
      outcomes.put(
        String.valueOf(requestId) + ':' + outcome.Outcome__c,
        outcome
      );
    }
    if (requestIds.isEmpty())
      return;

    Map<Id, Return_Request__c> requests = RefundNotificationSelector.requests(
      requestIds
    );
    Id typeId = RefundNotificationSelector.notificationTypeId();
    for (Refund_Notification__e outcome : outcomes.values()) {
      Return_Request__c request = requests.get(
        Id.valueOf(outcome.Request_Id__c)
      );
      if (request == null)
        continue;
      if (
        request.Store__r?.Store_Manager__c == null ||
        request.Store__r.Store_Manager__r.IsActive != true
      ) {
        LogService.warn(
          new List<SObject>{ request },
          'Refund notification skipped: the store has no active manager.',
          'RefundNotificationService',
          'deliver'
        );
        continue;
      }

      Boolean completed =
        outcome.Outcome__c == SmartReturnConstants.STATUS_COMPLETED;
      Messaging.CustomNotification notification = new Messaging.CustomNotification();
      notification.setNotificationTypeId(typeId);
      notification.setTargetId(request.Id);
      notification.setTitle(
        completed ? 'Hoàn tiền thành công' : 'Hoàn tiền thất bại'
      );
      notification.setBody(
        'Yêu cầu ' +
          request.Name +
          (completed
            ? ' đã hoàn tiền thành công.'
            : ' hoàn tiền thất bại. Kế toán cần đối soát.')
      );
      try {
        notification.send(
          new Set<String>{ String.valueOf(request.Store__r.Store_Manager__c) }
        );
        notificationsSent++;
      } catch (Exception error) {
        LogService.error(
          new List<SObject>{ request },
          error,
          'RefundNotificationService',
          'deliver'
        );
      }
    }
    LogService.insertLogs();
  }

  public class NotificationException extends Exception {
  }
}
