public class CreateReturnLineInput {
  @AuraEnabled
  public Id orderItemId { get; set; }

  @AuraEnabled
  public Decimal requestedQuantity { get; set; }

  @AuraEnabled
  public String reasonCode { get; set; }

  @AuraEnabled
  public String conditionCode { get; set; }
}
