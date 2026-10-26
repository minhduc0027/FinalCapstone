public with sharing class ReturnRequestController {
  /**
   * Loads the initial data for the Create Return page:
   * - Order header
   * - Order items
   * - Eligibility information
   * - Remaining quantities
   *
   * No DML operations are performed, so the result can be cached.
   */
  @AuraEnabled(cacheable=true)
  public static CreateReturnPageResult loadCreateReturnPage(Id orderId) {
    System.debug(
      LoggingLevel.INFO,
      'REQ-04 CONTROLLER | Load page' + ' | orderId=' + orderId
    );

    return ReturnPreviewService.loadCreateReturnPage(orderId);
  }

  /**
   * Recalculates the return preview when the user updates:
   * - Requested quantity
   * - Return reason
   * - Reported condition
   *
   * No DML operations are performed.
   *
   * Not marked as cacheable because remaining quantities
   * may change when other return requests are created.
   */
  @AuraEnabled
  public static CreateReturnPageResult previewReturn(CreateReturnInput input) {
    System.debug(
      LoggingLevel.INFO,
      'REQ-04 CONTROLLER | Preview' +
        ' | orderId=' +
        (input == null ? null : input.orderId) +
        ' | lineCount=' +
        (input == null || input.lines == null ? 0 : input.lines.size())
    );

    return ReturnPreviewService.previewReturn(input);
  }

  /**
   * Creates and submits a return request:
   * - Locks the related order items
   * - Validates REQ-05, REQ-06, and REQ-07 rules
   * - Creates the Return Request record
   * - Creates the Return Request Line records
   * - Initializes the approval routing process
   */
  @AuraEnabled
  public static CreateReturnResult createReturn(CreateReturnInput input) {
    System.debug(
      LoggingLevel.INFO,
      'REQ-04 CONTROLLER | Create Return' +
        ' | orderId=' +
        (input == null ? null : input.orderId) +
        ' | sourceChannel=' +
        (input == null ? null : input.sourceChannel) +
        ' | lineCount=' +
        (input == null || input.lines == null ? 0 : input.lines.size())
    );

    return ReturnIntakeService.createReturn(input);
  }
}
