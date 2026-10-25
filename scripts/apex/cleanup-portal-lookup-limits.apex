// TODO: Add this cleanup to the support-owned operations schedule.
// Keep active counters: both configured windows are bounded to at most 24 hours.
Datetime cutoff = System.now().addDays(-3);
List<Portal_Lookup_Limit__c> expired = [
  SELECT Id
  FROM Portal_Lookup_Limit__c
  WHERE LastModifiedDate < :cutoff
  ORDER BY LastModifiedDate
  LIMIT 10000
];
Database.delete(expired, false, AccessLevel.SYSTEM_MODE);
