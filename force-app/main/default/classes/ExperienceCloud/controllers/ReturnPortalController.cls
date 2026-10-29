public with sharing class ReturnPortalController {
  @AuraEnabled(cacheable=true)
  public static PortalReturnPage listRequests(Integer pageSize, String cursor) {
    try {
      return ReturnPortalService.listRequests(pageSize, cursor);
    } catch (ReturnPortalDomain.PortalException e) {
      throw new AuraHandledException(e.getMessage());
    } catch (Exception e) {
      throw serverError(e, 'LIST');
    }
  }

  @AuraEnabled(cacheable=true)
  public static PortalReturn getRequest(String requestNumber) {
    try {
      return ReturnPortalService.getRequest(requestNumber);
    } catch (ReturnPortalDomain.PortalException e) {
      throw new AuraHandledException(e.getMessage());
    } catch (Exception e) {
      throw serverError(e, 'DETAIL');
    }
  }

  private static AuraHandledException serverError(
    Exception e,
    String operation
  ) {
    String reference = EncodingUtil.convertToHex(Crypto.generateAesKey(128))
      .left(12);
    LogService.error(
      'Portal error ' + reference + ': ' + e.getTypeName(),
      'ReturnPortalController',
      operation
    );
    LogService.insertLogs();
    return new AuraHandledException(
      String.format(Label.SmartReturn_MSG_90, new List<String>{ reference })
    );
  }
}
