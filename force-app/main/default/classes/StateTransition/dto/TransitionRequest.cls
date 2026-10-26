public class TransitionRequest {
  public Id requestId;
  public String targetStatus;
  public String requiredApprovalLevel;
  public String rejectReason;
  public String internalStaffNote;

  public TransitionRequest(
    Id requestId,
    String targetStatus,
    String requiredApprovalLevel,
    String rejectReason,
    String internalStaffNote
  ) {
    this.requestId = requestId;
    this.targetStatus = targetStatus;
    this.requiredApprovalLevel = requiredApprovalLevel;
    this.rejectReason = rejectReason;
    this.internalStaffNote = internalStaffNote;
  }
}
