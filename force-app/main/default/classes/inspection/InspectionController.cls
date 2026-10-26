public with sharing class InspectionController {
  //===================================================
  // Load inspection detail
  //===================================================
  @AuraEnabled(cacheable=true)
  public static List<Return_Request_Line__c> getReturnRequestLines(
    Id returnRequestId
  ) {
    if (returnRequestId == null) {
      throw new AuraHandledException('Return Request Id is required.');
    }

    return ReturnRequestSelector.getReturnRequestLines(returnRequestId, false);
  }

  //===================================================
  // Submit inspection result
  //===================================================
  @AuraEnabled
  public static void submitInspection(
    List<Return_Request_Line__c> requestLines
  ) {
    if (requestLines == null || requestLines.isEmpty()) {
      throw new AuraHandledException('Inspection lines cannot be empty.');
    }

    InspectionService.processInspection(requestLines);
  }
}
