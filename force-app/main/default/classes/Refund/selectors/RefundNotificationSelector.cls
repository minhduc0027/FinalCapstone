public with sharing class RefundNotificationSelector {
  public static Id notificationTypeId() {
    DbQueryRequest request = new DbQueryRequest();
    request.objectName = 'CustomNotificationType';
    request.fields = new List<String>{ 'Id' };
    request.filters = new List<FilterCondition>{
      new FilterCondition('DeveloperName', '=', 'SmartReturn_Refund_Outcome')
    };
    request.pageSize = 1;
    return DbQueryService.execute(request, 1).records[0].Id;
  }

  public static Map<Id, Return_Request__c> requests(Set<Id> requestIds) {
    if (requestIds == null || requestIds.isEmpty())
      return new Map<Id, Return_Request__c>();

    DbQueryRequest request = new DbQueryRequest();
    request.objectName = 'Return_Request__c';
    request.fields = new List<String>{
      'Id',
      'Name',
      'Actual_Refund_Amount__c',
      'Store__r.Store_Manager__c',
      'Store__r.Store_Manager__r.IsActive'
    };
    request.filters = new List<FilterCondition>{
      new FilterCondition('Id', 'IN', new List<Id>(requestIds))
    };
    request.pageSize = requestIds.size();
    return new Map<Id, Return_Request__c>(
      (List<Return_Request__c>) DbQueryService.execute(
          request,
          requestIds.size()
        )
        .records
    );
  }
}
