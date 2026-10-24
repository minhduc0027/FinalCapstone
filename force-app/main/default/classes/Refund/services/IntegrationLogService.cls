public with sharing class IntegrationLogService {
  private static final String SYSTEM_NAME = 'PAYHUB';
  private static final String CALLBACK_ENDPOINT = '/services/apexrest/smartreturn/v1/refund-callback';

  public static Integration_Log__c outboundEntry(
    Refund_Transaction__c refund,
    String result,
    String errorCode,
    PayHubClient.Result response
  ) {
    return new Integration_Log__c(
      Refund_Transaction__c = refund.Id,
      System__c = SYSTEM_NAME,
      Direction__c = Direction.OUTBOUND.name(),
      Endpoint__c = PayHubClient.REFUND_PATH,
      Attempt_Number__c = refund.Attempt_Count__c,
      Request_Body__c = response == null ? null : response.requestBody,
      Response_Body__c = response == null ? null : response.responseBody,
      Http_Status__c = response == null ? null : response.httpStatus,
      Duration_Ms__c = response == null ? null : response.durationMs,
      Result__c = result,
      Error_Code__c = errorCode,
      Occurred_At__c = response == null ? System.now() : response.occurredAt
    );
  }

  public static void recordOutbound(
    Refund_Transaction__c refund,
    String result,
    String errorCode,
    PayHubClient.Result response
  ) {
    recordAll(
      new List<Integration_Log__c>{
        outboundEntry(refund, result, errorCode, response)
      }
    );
  }

  public static void recordAll(List<Integration_Log__c> entries) {
    requirePermission('Refund_Process');
    if (entries == null || entries.isEmpty())
      return;
    insert as system entries;
  }

  public static void recordCallback(
    Refund_Transaction__c refund,
    RefundDomain.Callback callback,
    String errorCode
  ) {
    requirePermission('Refund_Callback');
    Integer httpStatus = 200;
    if (refund == null)
      httpStatus = 404;
    else if (errorCode == 'PERSISTENCE_FAILED')
      httpStatus = 503;

    insert as system new Integration_Log__c(
      Refund_Transaction__c = refund == null ? null : refund.Id,
      System__c = SYSTEM_NAME,
      Direction__c = Direction.INBOUND.name(),
      Endpoint__c = CALLBACK_ENDPOINT,
      Request_Body__c = JSON.serialize(callback),
      Result__c = callback.status == 'SUCCESS' ? 'SUCCESS' : 'FAILED',
      Error_Code__c = errorCode == null ? callback.failureReason : errorCode,
      Http_Status__c = httpStatus,
      Occurred_At__c = System.now()
    );
  }

  public static void recordInvalidCallback() {
    requirePermission('Refund_Callback');
    insert as system new Integration_Log__c(
      System__c = SYSTEM_NAME,
      Direction__c = Direction.INBOUND.name(),
      Endpoint__c = CALLBACK_ENDPOINT,
      Result__c = 'FAILED',
      Error_Code__c = 'INVALID_CALLBACK',
      Http_Status__c = 400,
      Occurred_At__c = System.now()
    );
  }

  private static void requirePermission(String permission) {
    if (!FeatureManagement.checkPermission(permission)) {
      throw new IntegrationLogException(
        'You do not have permission to record PayHub exchanges'
      );
    }
  }

  public class IntegrationLogException extends Exception {
  }

  public enum Direction {
    OUTBOUND,
    INBOUND
  }
}
