public class ReturnRefundResult {
  @AuraEnabled
  public Decimal unitPricePaid { get; set; }

  @AuraEnabled
  public Decimal requestedQuantity { get; set; }

  @AuraEnabled
  public String reasonCode { get; set; }

  @AuraEnabled
  public String conditionCode { get; set; }

  @AuraEnabled
  public Decimal refundRate { get; set; }

  @AuraEnabled
  public Decimal rawRefundAmount { get; set; }

  @AuraEnabled
  public Decimal refundAmount { get; set; }

  @AuraEnabled
  public Boolean valid { get; set; }

  @AuraEnabled
  public String code { get; set; }

  @AuraEnabled
  public String message { get; set; }

  public static ReturnRefundResult create(
    Decimal unitPricePaid,
    Decimal requestedQuantity,
    String reasonCode,
    String conditionCode,
    Decimal refundRate,
    Decimal rawRefundAmount,
    Decimal refundAmount,
    Boolean valid,
    String code,
    String message
  ) {
    ReturnRefundResult result = new ReturnRefundResult();

    result.unitPricePaid = unitPricePaid;
    result.requestedQuantity = requestedQuantity;
    result.reasonCode = reasonCode;
    result.conditionCode = conditionCode;
    result.refundRate = refundRate;
    result.rawRefundAmount = rawRefundAmount;
    result.refundAmount = refundAmount;
    result.valid = valid;
    result.code = code;
    result.message = message;

    return result;
  }
}
