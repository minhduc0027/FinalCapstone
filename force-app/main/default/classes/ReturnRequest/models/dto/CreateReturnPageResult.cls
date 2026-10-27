public class CreateReturnPageResult {
  @AuraEnabled
  public Boolean success { get; set; }

  @AuraEnabled
  public CreateReturnOrderHeader header { get; set; }

  @AuraEnabled
  public List<CreateReturnOrderLine> lines { get; set; }

  @AuraEnabled
  public Decimal totalEstimatedRefund { get; set; }

  @AuraEnabled
  public String approvalLevel { get; set; }

  @AuraEnabled
  public Boolean canSubmit { get; set; }

  @AuraEnabled
  public String code { get; set; }

  @AuraEnabled
  public String message { get; set; }

  public CreateReturnPageResult() {
    lines = new List<CreateReturnOrderLine>();
    totalEstimatedRefund = 0;
    canSubmit = false;
  }
}
