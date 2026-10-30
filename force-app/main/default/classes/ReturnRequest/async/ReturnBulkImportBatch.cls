public without sharing class ReturnBulkImportBatch implements Database.Batchable<CreateReturnInput>, Database.Stateful {
  private List<CreateReturnInput> inputs;

  private Integer totalCount = 0;
  private Integer successCount = 0;
  private Integer failureCount = 0;

  private List<String> successMessages = new List<String>();

  private List<String> errorMessages = new List<String>();

  public ReturnBulkImportBatch(List<CreateReturnInput> inputs) {
    this.inputs = inputs == null ? new List<CreateReturnInput>() : inputs;
  }

  public Iterable<CreateReturnInput> start(Database.BatchableContext context) {
    return inputs;
  }

  public void execute(
    Database.BatchableContext context,
    List<CreateReturnInput> scope
  ) {
    for (CreateReturnInput input : scope) {
      totalCount++;

      String externalRequestId = input == null ? null : input.externalRequestId;

      try {
        /*
         * createReturn() is the transaction unit.
         *
         * Each request has its own Savepoint, validation,
         * OrderItem lock, header, lines and routing.
         */
        CreateReturnResult result = ReturnIntakeService.createReturn(input);

        if (result != null && result.success == true) {
          successCount++;

          successMessages.add(
            'SUCCESS' +
              ' | externalRequestId=' +
              externalRequestId +
              ' | requestId=' +
              result.returnRequestId +
              ' | requestNumber=' +
              result.returnRequestNumber +
              ' | status=' +
              result.status +
              ' | approvalLevel=' +
              result.approvalLevel +
              ' | estimatedRefund=' +
              result.estimatedRefundAmount
          );
        } else {
          failureCount++;

          String errorCode = result == null ? 'UNKNOWN_ERROR' : result.code;

          String errorMessage = result == null
            ? 'ReturnIntakeService returned no result.'
            : result.message;

          errorMessages.add(
            'ERROR' +
              ' | externalRequestId=' +
              externalRequestId +
              ' | code=' +
              errorCode +
              ' | message=' +
              errorMessage
          );
        }
      } catch (Exception exceptionRecord) {
        failureCount++;

        errorMessages.add(
          'ERROR' +
            ' | externalRequestId=' +
            externalRequestId +
            ' | type=' +
            exceptionRecord.getTypeName() +
            ' | message=' +
            exceptionRecord.getMessage()
        );
      }
    }

    System.debug(
      LoggingLevel.INFO,
      'UAT-01 | Scope completed' +
        ' | scopeSize=' +
        scope.size() +
        ' | totalProcessed=' +
        totalCount +
        ' | success=' +
        successCount +
        ' | failure=' +
        failureCount
    );
  }

  public void finish(Database.BatchableContext context) {
    AsyncApexJob job = [
      SELECT
        Id,
        Status,
        JobItemsProcessed,
        TotalJobItems,
        NumberOfErrors,
        ExtendedStatus
      FROM AsyncApexJob
      WHERE Id = :context.getJobId()
      LIMIT 1
    ];

    System.debug(
      LoggingLevel.ERROR,
      'UAT01_FINAL_RESULT' +
        '\nJOB_ID=' +
        job.Id +
        '\nJOB_STATUS=' +
        job.Status +
        '\nTOTAL_INPUTS=' +
        totalCount +
        '\nSUCCESS_COUNT=' +
        successCount +
        '\nFAILURE_COUNT=' +
        failureCount +
        '\nBATCH_ERRORS=' +
        job.NumberOfErrors
    );

    for (String successMessage : successMessages) {
      System.debug(LoggingLevel.ERROR, 'UAT01_RESULT | ' + successMessage);
    }

    for (String errorMessage : errorMessages) {
      System.debug(LoggingLevel.ERROR, 'UAT01_RESULT | ' + errorMessage);
    }
  }
}
