@RestResource(urlMapping='/smartreturn/v1/portal/lookup')
global with sharing class PortalGuestRest {
  @HttpPost
  global static void lookup() {
    RestResponse response = RestContext.response;
    response.addHeader('Content-Type', 'application/json; charset=UTF-8');
    response.addHeader('Cache-Control', 'no-store');
    response.addHeader('X-Content-Type-Options', 'nosniff');
    try {
      if (
        !FeatureManagement.checkPermission('SmartReturn_Portal_Guest_Lookup')
      ) {
        response.statusCode = 403;
        response.responseBody = Blob.valueOf('{"outcome":"DENIED"}');
        return;
      }
      Blob body = RestContext.request.requestBody;
      if (body == null || body.size() > 1024)
        throw new JSONException('Invalid request');
      LookupInput input = (LookupInput) JSON.deserializeStrict(
        body.toString(),
        LookupInput.class
      );
      if (input == null)
        throw new JSONException('Invalid request');
      Map<String, Object> result = PortalGuestService.lookup(
        input.requestNumber,
        input.phoneSuffix,
        RestContext.request.remoteAddress
      );
      response.statusCode = 200;
      response.responseBody = Blob.valueOf(JSON.serialize(result, true));
    } catch (JSONException e) {
      response.statusCode = 400;
      response.responseBody = Blob.valueOf('{"outcome":"INVALID_INPUT"}');
    } catch (ReturnPortalDomain.PortalException e) {
      response.statusCode = 400;
      response.responseBody = Blob.valueOf('{"outcome":"INVALID_INPUT"}');
    } catch (Exception e) {
      String reference = EncodingUtil.convertToHex(Crypto.generateAesKey(128))
        .left(12);
      LogService.error(
        'Portal error ' + reference + ': ' + e.getTypeName(),
        'PortalGuestRest',
        'LOOKUP'
      );
      LogService.insertLogs();
      response.statusCode = 500;
      response.responseBody = Blob.valueOf(
        JSON.serialize(
          new Map<String, Object>{
            'outcome' => 'ERROR',
            'reference' => reference
          }
        )
      );
    }
  }

  private class LookupInput {
    public String requestNumber;
    public String phoneSuffix;
  }
}
