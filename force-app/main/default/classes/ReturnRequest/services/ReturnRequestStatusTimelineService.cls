public with sharing class ReturnRequestStatusTimelineService {
  public class StatusTimelineItem {
    @AuraEnabled
    public String previousStatus { get; set; }

    @AuraEnabled
    public String currentStatus { get; set; }

    @AuraEnabled
    public Datetime changedAt { get; set; }

    @AuraEnabled
    public String changedByName { get; set; }

    @AuraEnabled
    public Boolean currentStep { get; set; }
  }

  public static List<StatusTimelineItem> getStatusTimeline(Id requestId) {
    if (requestId == null) {
      return new List<StatusTimelineItem>();
    }

    List<Return_Request__History> histories = [
      SELECT OldValue, NewValue, CreatedDate, CreatedBy.Name
      FROM Return_Request__History
      WHERE ParentId = :requestId AND Field = 'Status__c'
      ORDER BY CreatedDate ASC
    ];

    List<StatusTimelineItem> result = new List<StatusTimelineItem>();

    Integer lastIndex = histories.size() - 1;

    for (Integer i = 0; i < histories.size(); i++) {
      Return_Request__History history = histories[i];

      StatusTimelineItem item = new StatusTimelineItem();

      item.previousStatus = history.OldValue == null
        ? null
        : String.valueOf(history.OldValue);

      item.currentStatus = history.NewValue == null
        ? null
        : String.valueOf(history.NewValue);

      item.changedAt = history.CreatedDate;

      item.changedByName = history.CreatedBy == null
        ? null
        : history.CreatedBy.Name;

      item.currentStep = i == lastIndex;

      result.add(item);
    }

    return result;
  }
}
