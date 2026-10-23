public class CreateReturnInput {
  @AuraEnabled
  public Id orderId { get; set; }

  @AuraEnabled
  public String sourceChannel { get; set; }

  @AuraEnabled
  public String externalRequestId { get; set; }

  @AuraEnabled
  public List<CreateReturnLineInput> lines { get; set; }
}
