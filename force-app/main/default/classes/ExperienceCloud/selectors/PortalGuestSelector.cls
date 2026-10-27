/**
 * Narrow system-access boundary for the guest lookup service. Guest users have no
 * direct object access; the service checks the custom permission and phone proof.
 * This class has no remotely callable methods and never returns data to a browser.
 */
public without sharing class PortalGuestSelector {
  public static List<Return_Request__c> requestByNumber(String requestNumber) {
    return [
      SELECT
        Id,
        Name,
        Status__c,
        CreatedDate,
        Customer__r.Phone,
        Rejection_Reason__c
      FROM Return_Request__c
      WHERE Name = :requestNumber
      WITH SYSTEM_MODE
      LIMIT 1
    ];
  }

  public static List<Portal_Lookup_Limit__c> counter(String fingerprint) {
    return [
      SELECT
        Id,
        Fingerprint__c,
        Failure_Count__c,
        Window_Started_At__c,
        Locked_Until__c
      FROM Portal_Lookup_Limit__c
      WHERE Fingerprint__c = :fingerprint
      WITH SYSTEM_MODE
      LIMIT 1
      FOR UPDATE
    ];
  }

  public static List<Return_Request_Line__c> lines(Id authorizedRequestId) {
    return [
      SELECT Product__c, Product__r.Name, Requested_Quantity__c
      FROM Return_Request_Line__c
      WHERE Return_Request__c = :authorizedRequestId
      WITH SYSTEM_MODE
      ORDER BY Id
      LIMIT 1001
    ];
  }

  public static List<Return_Request__History> history(Id authorizedRequestId) {
    return [
      SELECT NewValue, CreatedDate
      FROM Return_Request__History
      WHERE ParentId = :authorizedRequestId AND Field = 'Status__c'
      WITH SYSTEM_MODE
      ORDER BY CreatedDate, Id
      LIMIT 1001
    ];
  }
}
