public with sharing class InspectionRow {
  @AuraEnabled
  public Id requestId { get; set; }

  @AuraEnabled
  public String requestName { get; set; }

  @AuraEnabled
  public String customerName { get; set; }

  @AuraEnabled
  public String storeName { get; set; }

  @AuraEnabled
  public String sourceChannel { get; set; }

  @AuraEnabled
  public Decimal estimatedRefundAmount { get; set; }

  @AuraEnabled
  public Datetime createdDate { get; set; }

  public static InspectionRow fromRecord(Return_Request__c recordValue) {
    InspectionRow row = new InspectionRow();

    row.requestId = recordValue.Id;
    row.requestName = recordValue.Name;

    row.sourceChannel = recordValue.Source_Channel__c;

    row.estimatedRefundAmount = recordValue.Estimated_Refund_Amount__c;

    row.createdDate = recordValue.CreatedDate;

    if (recordValue.Customer__r != null) {
      row.customerName = recordValue.Customer__r.Name;
    }

    if (recordValue.Store__r != null) {
      row.storeName = recordValue.Store__r.Name;
    }

    return row;
  }
}
