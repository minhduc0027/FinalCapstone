@RestResource(urlMapping='/smartreturn/v1/refund-callback')
global with sharing class RefundCallbackRest {
  @HttpPost
  global static void receive() {
    RestContext.response.addHeader('Content-Type', 'application/json');
    if (!FeatureManagement.checkPermission('Refund_Callback')) {
      respond(403, RefundCallBackResult.FORBIDDEN.name());
      return;
    }

    try {
      if (
        RestContext.request.requestBody == null ||
        RestContext.request.requestBody.size() > 16384
      ) {
        IntegrationLogService.recordInvalidCallback();
        respond(400, RefundCallBackResult.INVALID_CALLBACK.name());
        return;
      }

      RefundDomain.Callback payload = (RefundDomain.Callback) JSON.deserializeStrict(
        RestContext.request.requestBody.toString(),
        RefundDomain.Callback.class
      );

      Integer status = RefundService.handleCallback(payload);
      respond(
        status,
        status == 200
          ? RefundCallBackResult.RECORDED.name()
          : (status == 404
              ? RefundCallBackResult.REQUEST_NOT_FOUND.name()
              : RefundCallBackResult.PERSISTENCE_FAILED.name())
      );
    } catch (JSONException e) {
      IntegrationLogService.recordInvalidCallback();
      respond(400, RefundCallBackResult.INVALID_CALLBACK.name());
    } catch (RefundDomain.RuleException e) {
      IntegrationLogService.recordInvalidCallback();
      respond(400, RefundCallBackResult.INVALID_CALLBACK.name());
    } catch (Exception e) {
      respond(503, RefundCallBackResult.INTERNAL_ERROR.name());
    }
  }

  private static void respond(Integer code, String message) {
    RestContext.response.statusCode = code;
    RestContext.response.responseBody = Blob.valueOf(
      JSON.serialize(new Map<String, Object>{ 'result' => message })
    );
  }

  public enum RefundCallbackResult {
    RECORDED,
    REQUEST_NOT_FOUND,
    PERSISTENCE_FAILED,
    INVALID_CALLBACK,
    INTERNAL_ERROR,
    FORBIDDEN
  }
}
