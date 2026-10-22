public class ReturnEligibilityResult {
  @AuraEnabled
  public Id orderItemId { get; set; }

  @AuraEnabled
  public Boolean eligible { get; set; }

  @AuraEnabled
  public String code { get; set; }

  @AuraEnabled
  public String message { get; set; }

  @AuraEnabled
  public Date returnDeadline { get; set; }

  public static ReturnEligibilityResult success(
    Id orderItemId,
    Date returnDeadline
  ) {
    ReturnEligibilityResult result = new ReturnEligibilityResult();
    result.orderItemId = orderItemId;
    result.eligible = true;
    result.code = 'ELIGIBLE';
    result.message = 'Sản phẩm đủ điều kiện trả hàng.';
    result.returnDeadline = returnDeadline;
    return result;
  }

  public static ReturnEligibilityResult failure(
    Id orderItemId,
    String code,
    String message,
    Date returnDeadline
  ) {
    ReturnEligibilityResult result = new ReturnEligibilityResult();
    result.orderItemId = orderItemId;
    result.eligible = false;
    result.code = code;
    result.message = message;
    result.returnDeadline = returnDeadline;
    return result;
  }
}
