public with sharing class PayHubClient {
  public static final String REFUND_PATH = '/v1/refunds';
  public static final String ENDPOINT = 'callout:PayHub' + REFUND_PATH;

  public class Result {
    public Integer httpStatus;
    public String status;
    public String refundId;
    public String errorCode;
    public Boolean transportFailure = false;
    public Boolean invalidResponse = false;
    public String requestBody;
    public String responseBody;
    public Datetime occurredAt;
    public Long durationMs;
  }

  public static Result send(
    String merchantRef,
    String orderNumber,
    Decimal amount,
    String key,
    Integer timeoutMs
  ) {
    if (
      String.isBlank(merchantRef) ||
      String.isBlank(orderNumber) ||
      String.isBlank(key) ||
      amount == null ||
      amount <= 0 ||
      amount != amount.setScale(0)
    ) {
      throw new ClientException('Invalid refund payment instruction.');
    }
    Result result = new Result();
    result.occurredAt = System.now();
    result.requestBody = JSON.serialize(
      new Map<String, Object>{
        'merchantRef' => merchantRef,
        'orderNumber' => orderNumber,
        'amount' => amount,
        'currency' => 'VND',
        'reason' => 'CUSTOMER_RETURN'
      }
    );

    HttpRequest request = new HttpRequest();
    request.setEndpoint(ENDPOINT);
    request.setMethod('POST');
    request.setHeader('Content-Type', 'application/json');
    request.setHeader('Idempotency-Key', key);
    request.setTimeout(timeoutMs);
    request.setBody(result.requestBody);

    try {
      HttpResponse response = new Http().send(request);
      result.httpStatus = response.getStatusCode();

      try {
        Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(
          response.getBody()
        );
        if (body == null) {
          result.invalidResponse = true;
        } else {
          result.status = safeCode(body.get('status'), 20);
          result.refundId = safeCode(body.get('refundId'), 80);
          result.errorCode = safeCode(body.get('errorCode'), 100);
          result.responseBody = JSON.serialize(
            new Map<String, Object>{
              'status' => result.status,
              'refundId' => result.refundId,
              'errorCode' => result.errorCode
            }
          );
        }
      } catch (JSONException e) {
        result.invalidResponse = true;
      } catch (TypeException e) {
        result.invalidResponse = true;
      }
    } catch (CalloutException e) {
      result.transportFailure = true;
      result.errorCode = 'TRANSPORT_ERROR';
    }

    result.durationMs = System.now().getTime() - result.occurredAt.getTime();
    return result;
  }

  public static String safeCode(Object value, Integer maxLength) {
    if (!(value instanceof String)) {
      return null;
    }
    String code = (String) value;
    return code.length() <= maxLength &&
      Pattern.matches('[A-Za-z0-9_\\-]+', code)
      ? code
      : null;
  }

  public class ClientException extends Exception {
  }
}
