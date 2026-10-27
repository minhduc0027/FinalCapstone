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
  public Datetime approvalDueAt;

  @AuraEnabled
  public String sourceChannel;

  @AuraEnabled
  public Boolean overdue;

  public static ApprovalRow fromRecord(Return_Request__c requestRecord) {
    ApprovalRow row = new ApprovalRow();

    row.requestId = requestRecord.Id;
    row.requestName = requestRecord.Name;
    row.status = requestRecord.Status__c;
    row.approvalLevel = requestRecord.Required_Approval_Level__c;
    row.approverId = requestRecord.ApproverId__c;
    row.estimatedRefundAmount = requestRecord.Estimated_Refund_Amount__c;
    row.actualRefundAmount = requestRecord.Actual_Refund_Amount__c;
    row.createdDate = requestRecord.CreatedDate;
    row.sourceChannel = requestRecord.Source_Channel__c;

    if (requestRecord.Approval_Due_At__c != null) {
      row.approvalDueAt = requestRecord.Approval_Due_At__c;
      row.overdue = requestRecord.Approval_Due_At__c < System.now();
    }

    if (requestRecord.Customer__r != null) {
      row.customerName = requestRecord.Customer__r.Name;
    }

    if (requestRecord.Store__r != null) {
      row.storeName = requestRecord.Store__r.Name;
    }

    return row;
  }
}
