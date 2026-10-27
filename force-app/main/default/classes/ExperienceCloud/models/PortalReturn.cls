public class PortalReturn {
  @AuraEnabled
  public String requestNumber;
  @AuraEnabled
  public String status;
  @AuraEnabled
  public Datetime createdAt;
  @AuraEnabled
  public Decimal refundAmount;
  @AuraEnabled
  public String amountKind;
  @AuraEnabled
  public String rejectionReason;
  @AuraEnabled
  public List<PortalReturnLine> lines = new List<PortalReturnLine>();
  @AuraEnabled
  public List<PortalStatusChange> history = new List<PortalStatusChange>();
}
