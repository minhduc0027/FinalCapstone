public with sharing class ApprovalActionResult {
  @AuraEnabled
  public Id requestId { get; set; }

  @AuraEnabled
  public Boolean success { get; set; }

  @AuraEnabled
  public String message { get; set; }

  public ApprovalActionResult(Id requestId, Boolean success, String message) {
    this.requestId = requestId;
    this.success = success;
    this.message = message;
  }

  public static ApprovalActionResult success(Id requestId) {
    return new ApprovalActionResult(requestId, true, 'SUCCESS');
  }

  public static ApprovalActionResult failure(Id requestId, String message) {
    return new ApprovalActionResult(requestId, false, message);
  }
}
