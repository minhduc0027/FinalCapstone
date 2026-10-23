public class CreateReturnResult {
  @AuraEnabled
  public Boolean success { get; set; }

  @AuraEnabled
  public Id returnRequestId { get; set; }

  @AuraEnabled
  public String returnRequestNumber { get; set; }

  @AuraEnabled
  public String status { get; set; }

  @AuraEnabled
  public String approvalLevel { get; set; }

  @AuraEnabled
  public Decimal estimatedRefundAmount { get; set; }

  @AuraEnabled
  public String code { get; set; }

  @AuraEnabled
  public String message { get; set; }

  public static CreateReturnResult success(Return_Request__c requestRecord) {
    CreateReturnResult result = new CreateReturnResult();

    result.success = true;
    result.returnRequestId = requestRecord.Id;
    result.returnRequestNumber = requestRecord.Name;
    result.status = requestRecord.Status__c;
    result.approvalLevel = requestRecord.Required_Approval_Level__c;
    result.estimatedRefundAmount = requestRecord.Estimated_Refund_Amount__c;
    result.code = 'RETURN_REQUEST_CREATED';
    result.message = 'Yêu cầu trả hàng đã được tạo thành công.';

    return result;
  }

  public static CreateReturnResult failure(String code, String message) {
    CreateReturnResult result = new CreateReturnResult();

    result.success = false;
    result.code = code;
    result.message = message;

    return result;
  }
}
