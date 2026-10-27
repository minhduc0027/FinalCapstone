public class ReturnApiException extends Exception {
  public Integer statusCode { get; private set; }
  public String errorCode { get; private set; }

  public ReturnApiException(
    Integer statusCode,
    String errorCode,
    String message
  ) {
    this.statusCode = statusCode;
    this.errorCode = errorCode;
    this.setMessage(message);
  }
}
