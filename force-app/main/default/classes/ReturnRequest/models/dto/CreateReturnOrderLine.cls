public class CreateReturnOrderLine {
  @AuraEnabled
  public Id orderItemId { get; set; }

  @AuraEnabled
  public Id productId { get; set; }

  @AuraEnabled
  public String productName { get; set; }

  @AuraEnabled
  public String sku { get; set; }

  @AuraEnabled
  public String productFamily { get; set; }

  @AuraEnabled
  public Decimal unitPricePaid { get; set; }

  @AuraEnabled
  public Decimal purchasedQuantity { get; set; }

  @AuraEnabled
  public Decimal activeReturnedQuantity { get; set; }

  @AuraEnabled
  public Decimal remainingQuantity { get; set; }

  @AuraEnabled
  public Date returnDeadline { get; set; }

  @AuraEnabled
  public Boolean eligible { get; set; }

  @AuraEnabled
  public String eligibilityCode { get; set; }

  @AuraEnabled
  public String eligibilityReason { get; set; }

  /*
   * Fields below will be automatically updated when user changed values
   */
  @AuraEnabled
  public Decimal requestedQuantity { get; set; }

  @AuraEnabled
  public String reasonCode { get; set; }

  @AuraEnabled
  public String conditionCode { get; set; }

  @AuraEnabled
  public Decimal refundRate { get; set; }

  @AuraEnabled
  public Decimal estimatedRefundAmount { get; set; }

  @AuraEnabled
  public Boolean valid { get; set; }

  @AuraEnabled
  public String validationMessage { get; set; }
}
