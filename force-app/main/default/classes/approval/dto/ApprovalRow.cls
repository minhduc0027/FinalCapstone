public with sharing class ApprovalRow {
  @AuraEnabled
  public Id requestId { get; set; }

  @AuraEnabled
  public String requestName { get; set; }

  @AuraEnabled
  public String status { get; set; }

  @AuraEnabled
  public String approvalLevel { get; set; }

  @AuraEnabled
  public Id approverId { get; set; }

  @AuraEnabled
  public String customerName { get; set; }

  @AuraEnabled
  public String storeName { get; set; }

  @AuraEnabled
  public Decimal estimatedRefundAmount { get; set; }

  @AuraEnabled
  public Decimal actualRefundAmount { get; set; }

  @AuraEnabled
  public Datetime createdDate { get; set; }

  @AuraEnabled
  public Integer waitingHours { get; set; }

  public static ApprovalWorklistRow fromRecord(
    Return_Request__c requestRecord
  ) {
    ApprovalWorklistRow row = new ApprovalWorklistRow();

    row.requestId = requestRecord.Id;
    row.requestName = requestRecord.Name;
    row.status = requestRecord.Status__c;
    row.approvalLevel = requestRecord.Required_Approval_Level__c;
    row.approverId = requestRecord.ApproverId__c;
    row.estimatedRefundAmount = requestRecord.Estimated_Refund_Amount__c;
    row.actualRefundAmount = requestRecord.Actual_Refund_Amount__c;
    row.createdDate = requestRecord.CreatedDate;

    if (requestRecord.Customer__r != null) {
      row.customerName = requestRecord.Customer__r.Name;
    }

    if (requestRecord.Store__r != null) {
      row.storeName = requestRecord.Store__r.Name;
    }

    if (requestRecord.CreatedDate != null) {
      Long elapsedMilliseconds =
        System.now().getTime() - requestRecord.CreatedDate.getTime();

      row.waitingHours = Integer.valueOf(
        elapsedMilliseconds / (1000 * 60 * 60)
      );
    }

    return row;
  }
}
