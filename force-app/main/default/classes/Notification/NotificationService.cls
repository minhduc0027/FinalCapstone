public with sharing class NotificationService {
  private static final String NOTIFICATION_TYPE_DEVELOPER_NAME = 'SmartReturn_Notification';

  @TestVisible
  private static Id cachedNotificationTypeId;

  //===================================================
  // Strict send
  //===================================================
  public static void send(
    Set<Id> recipientIds,
    Id targetId,
    String title,
    String body
  ) {
    Set<String> normalizedRecipientIds = normalizeRecipientIds(recipientIds);

    if (normalizedRecipientIds.isEmpty()) {
      return;
    }

    if (targetId == null) {
      throw new NotificationException('Notification target is required.');
    }

    if (String.isBlank(title)) {
      throw new NotificationException('Notification title is required.');
    }

    if (String.isBlank(body)) {
      throw new NotificationException('Notification body is required.');
    }

    Id notificationTypeId = getNotificationTypeId();

    Messaging.CustomNotification notification = new Messaging.CustomNotification();

    notification.setNotificationTypeId(notificationTypeId);
    notification.setTitle(title.trim());
    notification.setBody(body.trim());
    notification.setTargetId(targetId);

    try {
      notification.send(normalizedRecipientIds);
    } catch (Exception e) {
      throw new NotificationException(
        'Unable to send notification: ' + e.getMessage()
      );
    }
  }

  //===================================================
  // Best-effort send
  //===================================================
  public static Boolean trySend(
    Set<Id> recipientIds,
    Id targetId,
    String title,
    String body
  ) {
    try {
      send(recipientIds, targetId, title, body);

      return true;
    } catch (Exception e) {
      LogService.error(e, 'NotificationService', 'trySend');
      LogService.insertLogs();
      return false;
    }
  }

  //===================================================
  // Custom Notification Type
  //===================================================
  @TestVisible
  private static Id getNotificationTypeId() {
    if (cachedNotificationTypeId != null) {
      return cachedNotificationTypeId;
    }

    List<CustomNotificationType> notificationTypes = [
      SELECT Id, DeveloperName
      FROM CustomNotificationType
      WHERE DeveloperName = :NOTIFICATION_TYPE_DEVELOPER_NAME
      LIMIT 1
    ];

    if (notificationTypes.isEmpty()) {
      throw new NotificationException(
        'Custom Notification Type "' +
          NOTIFICATION_TYPE_DEVELOPER_NAME +
          '" is not configured.'
      );
    }

    cachedNotificationTypeId = notificationTypes[0].Id;

    return cachedNotificationTypeId;
  }

  //===================================================
  // Recipient normalization
  //===================================================
  @TestVisible
  private static Set<String> normalizeRecipientIds(Set<Id> recipientIds) {
    Set<String> normalizedRecipientIds = new Set<String>();

    if (recipientIds == null) {
      return normalizedRecipientIds;
    }

    for (Id recipientId : recipientIds) {
      if (recipientId != null) {
        normalizedRecipientIds.add(String.valueOf(recipientId));
      }
    }

    return normalizedRecipientIds;
  }

  public class NotificationException extends Exception {
  }
}
