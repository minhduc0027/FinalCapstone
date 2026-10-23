public class TransitionResult {
  public Id requestId;
  public Boolean success;
  public String message;

  public TransitionResult(Id requestId, Boolean success, String message) {
    this.requestId = requestId;
    this.success = success;
    this.message = message;
  }
}
