@IsTest
private class PayHubClientTest {
  private class Mock implements HttpCalloutMock {
    Integer code;
    String body;
    Boolean timeout;
    Mock(Integer code, String body, Boolean timeout) {
      this.code = code;
      this.body = body;
      this.timeout = timeout;
    }
    public HttpResponse respond(HttpRequest request) {
      Assert.areEqual(
        'callout:PayHub/v1/refunds',
        request.getEndpoint(),
        'Use the Named Credential.'
      );
      Assert.areEqual('POST', request.getMethod(), 'INT-03 is POST.');
      Assert.areEqual(
        'RR-2610-00015',
        request.getHeader('Idempotency-Key'),
        'Reuse request identity.'
      );
      Assert.isNull(
        request.getHeader('Authorization'),
        'Named Credential owns authentication.'
      );
      Assert.isNull(
        request.getHeader('X-Mock-Scenario'),
        'No mock headers in Apex.'
      );
      Map<String, Object> payload = (Map<String, Object>) JSON.deserializeUntyped(
        request.getBody()
      );
      Assert.areEqual('VND', payload.get('currency'), 'Only integer VND.');
      Assert.areEqual(
        Decimal.valueOf('1992000'),
        payload.get('amount'),
        'Send actual amount.'
      );
      if (timeout) {
        throw new CalloutException(
          'Read timed out: secret must never be logged'
        );
      }
      HttpResponse response = new HttpResponse();
      response.setStatusCode(code);
      response.setBody(body);
      return response;
    }
  }
  private static PayHubClient.Result invoke(
    Integer code,
    String body,
    Boolean timeout
  ) {
    Test.setMock(HttpCalloutMock.class, new Mock(code, body, timeout));
    return PayHubClient.send(
      'RR-2610-00015',
      '00012345',
      1992000,
      'RR-2610-00015'
    );
  }
  @IsTest
  static void success() {
    Test.startTest();
    PayHubClient.Result result = invoke(
      200,
      '{"refundId":"PH-RF-88231","status":"SUCCESS"}',
      false
    );
    Test.stopTest();
    Assert.areEqual('SUCCESS', result.status, 'Parse provider outcome.');
    Assert.areEqual(
      'PH-RF-88231',
      result.refundId,
      'Retain provider identity.'
    );
  }
  @IsTest
  static void pending() {
    Test.startTest();
    PayHubClient.Result result = invoke(
      200,
      '{"refundId":"PH-RF-88231","status":"PENDING"}',
      false
    );
    Test.stopTest();
    Assert.areEqual('PENDING', result.status, 'Preserve pending outcome.');
  }
  @IsTest
  static void invalidAmount() {
    Test.startTest();
    PayHubClient.Result result = invoke(
      422,
      '{"errorCode":"INVALID_AMOUNT"}',
      false
    );
    Test.stopTest();
    Assert.areEqual(
      'INVALID_AMOUNT',
      result.errorCode,
      'Preserve validation code.'
    );
    Assert.areEqual(422, result.httpStatus, 'Preserve HTTP status.');
  }
  @IsTest
  static void http500() {
    Test.startTest();
    PayHubClient.Result result = invoke(500, '{}', false);
    Test.stopTest();
    Assert.areEqual(500, result.httpStatus, 'Preserve system error.');
  }
  @IsTest
  static void http503() {
    Test.startTest();
    PayHubClient.Result result = invoke(503, '{}', false);
    Test.stopTest();
    Assert.areEqual(503, result.httpStatus, 'Preserve unavailable status.');
  }
  @IsTest
  static void timeoutIsUncertain() {
    Test.startTest();
    PayHubClient.Result result = invoke(null, null, true);
    Test.stopTest();
    Assert.isTrue(result.transportFailure, 'Timeout is transport uncertainty.');
    Assert.isNull(result.httpStatus, 'No fabricated HTTP status.');
    Assert.isNull(result.responseBody, 'No exception or auth data in audit.');
  }
  @IsTest
  static void malformedResponse() {
    Test.startTest();
    PayHubClient.Result result = invoke(200, '<html>secret</html>', false);
    Test.stopTest();
    Assert.isTrue(result.invalidResponse, 'Invalid JSON must be controlled.');
    Assert.isNull(result.responseBody, 'Do not log arbitrary HTML.');
  }
  @IsTest
  static void responseAllowlist() {
    Test.startTest();
    PayHubClient.Result result = invoke(
      200,
      '{"status":"SUCCESS","refundId":"PH-RF-1","accessToken":"secret"}',
      false
    );
    Test.stopTest();
    Assert.isFalse(
      result.responseBody.contains('secret'),
      'Drop unknown sensitive fields.'
    );
  }
  @IsTest
  static void invalidPayloadBeforeCallout() {
    Test.startTest();
    try {
      PayHubClient.send('RR-1', 'O-1', 1.5, 'RR-1');
      Assert.fail('Fractional VND must not be sent.');
    } catch (PayHubClient.ClientException e) {
      Assert.isTrue(
        e.getMessage().contains('Invalid refund payment instruction'),
        'Explain invalid payment.'
      );
    }
    Test.stopTest();
    Assert.areEqual(0, Limits.getCallouts(), 'No HTTP for invalid input.');
  }

  @IsTest
  static void configuredTimeoutConvertsSecondsToMilliseconds() {
    PayHubClient.timeoutSecondsOverride = 5;

    Test.startTest();
    Integer timeoutMs = PayHubClient.configuredTimeoutMs();
    Test.stopTest();
    Assert.areEqual(
      5000,
      timeoutMs,
      'Convert configured seconds to milliseconds.'
    );
  }

  @IsTest
  static void zeroTimeoutIsRejected() {
    PayHubClient.timeoutSecondsOverride = 0;

    Test.startTest();
    try {
      PayHubClient.configuredTimeoutMs();
      Assert.fail('Zero timeout must be rejected.');
    } catch (PayHubClient.ConfigurationException e) {
      Assert.isTrue(
        e.getMessage().contains('between 1 and 120'),
        'Explain the valid range.'
      );
    }
    Test.stopTest();
  }

  @IsTest
  static void excessiveTimeoutIsRejected() {
    PayHubClient.timeoutSecondsOverride = 121;

    Test.startTest();
    try {
      PayHubClient.configuredTimeoutMs();
      Assert.fail('Timeout above the platform limit must be rejected.');
    } catch (PayHubClient.ConfigurationException e) {
      Assert.isTrue(
        e.getMessage().contains('between 1 and 120'),
        'Explain the valid range.'
      );
    }
    Test.stopTest();
  }
}
