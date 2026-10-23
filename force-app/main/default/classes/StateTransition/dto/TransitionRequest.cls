public class TransitionRequest {
  public Id requestId;
  public String targetStatus;
  public String requiredApprovalLevel;

  public TransitionRequest(
    Id requestId,
    String targetStatus,
    String requiredApprovalLevel
  ) {
    this.requestId = requestId;
    this.targetStatus = targetStatus;
    this.requiredApprovalLevel = requiredApprovalLevel;
  }
}
