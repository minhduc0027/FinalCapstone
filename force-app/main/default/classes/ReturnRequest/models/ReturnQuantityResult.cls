public class ReturnQuantityResult {
  @AuraEnabled
  public Id orderItemId { get; set; }

  @AuraEnabled
  public Decimal purchasedQuantity { get; set; }

  @AuraEnabled
  public Decimal activeReturnedQuantity { get; set; }

  @AuraEnabled
  public Decimal remainingQuantity { get; set; }

  @AuraEnabled
  public Decimal requestedQuantity { get; set; }

  @AuraEnabled
  public Boolean valid { get; set; }

  @AuraEnabled
  public String code { get; set; }

  @AuraEnabled
  public String message { get; set; }

  public static ReturnQuantityResult create(
    Id orderItemId,
    Decimal purchasedQuantity,
    Decimal activeReturnedQuantity,
    Decimal requestedQuantity,
    Boolean valid,
    String code,
    String message
  ) {
    ReturnQuantityResult result = new ReturnQuantityResult();

    result.orderItemId = orderItemId;
    result.purchasedQuantity = purchasedQuantity == null
      ? 0
      : purchasedQuantity;

    result.activeReturnedQuantity = activeReturnedQuantity == null
      ? 0
      : activeReturnedQuantity;

    result.remainingQuantity = Math.max(
      0,
      result.purchasedQuantity - result.activeReturnedQuantity
    );

    result.requestedQuantity = requestedQuantity == null
      ? 0
      : requestedQuantity;

    result.valid = valid;
    result.code = code;
    result.message = message;

    return result;
  }
}
