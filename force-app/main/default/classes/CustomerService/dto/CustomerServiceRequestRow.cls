public with sharing class CustomerServiceRequestRow {
  @AuraEnabled
  public Id requestId { get; set; }

  @AuraEnabled
  public String requestName { get; set; }

  @AuraEnabled
  public String customerName { get; set; }

  @AuraEnabled
  public String customerPhone { get; set; }

  @AuraEnabled
  public String orderNumber { get; set; }

  @AuraEnabled
  public String storeName { get; set; }

  @AuraEnabled
  public String status { get; set; }

  @AuraEnabled
  public Decimal estimatedRefundAmount { get; set; }

  @AuraEnabled
  public Decimal actualRefundAmount { get; set; }

  @AuraEnabled
  public Datetime createdDate { get; set; }

  public static CustomerServiceRequestRow fromRecord(
    Return_Request__c requestRecord
  ) {
    CustomerServiceRequestRow row = new CustomerServiceRequestRow();

    row.requestId = requestRecord.Id;
    row.requestName = requestRecord.Name;
    row.status = requestRecord.Status__c;
    row.estimatedRefundAmount = requestRecord.Estimated_Refund_Amount__c;
    row.actualRefundAmount = requestRecord.Actual_Refund_Amount__c;
    row.createdDate = requestRecord.CreatedDate;

    if (requestRecord.Customer__r != null) {
      row.customerName = requestRecord.Customer__r.Name;
      row.customerPhone = requestRecord.Customer__r.Phone;
    }

    if (requestRecord.Order__r != null) {
      row.orderNumber = requestRecord.Order__r.OrderNumber;
    }

    if (requestRecord.Store__r != null) {
      row.storeName = requestRecord.Store__r.Name;
    }

    return row;
  }
}
