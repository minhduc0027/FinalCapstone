public without sharing class ApplicationLogEventHandler {
  public static void handle(List<Application_Log_Event__e> events) {
    if (events == null || events.isEmpty()) {
      return;
    }

    Set<String> eventKeys = new Set<String>();
    for (Application_Log_Event__e eventRecord : events) {
      if (String.isNotBlank(eventRecord.Event_Key__c)) {
        eventKeys.add(eventRecord.Event_Key__c);
      }
    }

    Set<String> existingKeys = new Set<String>();
    if (!eventKeys.isEmpty()) {
      for (Application_Log__c existingLog : [
        SELECT Event_Key__c
        FROM Application_Log__c
        WHERE Event_Key__c IN :eventKeys
      ]) {
        existingKeys.add(existingLog.Event_Key__c);
      }
    }

    List<Application_Log__c> logs = new List<Application_Log__c>();

    for (Application_Log_Event__e eventRecord : events) {
      if (
        String.isNotBlank(eventRecord.Event_Key__c) &&
        existingKeys.contains(eventRecord.Event_Key__c)
      ) {
        continue;
      }

      logs.add(
        new Application_Log__c(
          Level__c = eventRecord.Level__c,
          Message__c = eventRecord.Message__c,
          Source__c = eventRecord.Source__c,
          Operation__c = eventRecord.Operation__c,
          RelatedRecord__c = toId(eventRecord.RelatedRecord__c),
          Transaction_Id__c = eventRecord.Transaction_Id__c,
          UserId__c = toId(eventRecord.UserId__c),
          Stack_Trace__c = eventRecord.Stack_Trace__c,
          Event_Key__c = eventRecord.Event_Key__c,
          Logged_At__c = eventRecord.Logged_At__c
        )
      );
    }

    if (!logs.isEmpty()) {
      Database.insert(logs, false);
    }
  }

  private static Id toId(String value) {
    if (String.isBlank(value)) {
      return null;
    }
    try {
      return (Id) value;
    } catch (Exception ignored) {
      return null;
    }
  }
}
