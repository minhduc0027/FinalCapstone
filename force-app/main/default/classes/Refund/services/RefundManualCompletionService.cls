/** Persists the controlled Accounting action while normal record access remains read-only. */
public without sharing class RefundManualCompletionService {
  /** Completes records already read and locked by the manual-completion entry point. */
  public static void complete(
    Refund_Transaction__c refund,
    Return_Request__c request,
    String externalReference
  ) {
    if (!FeatureManagement.checkPermission('Refund_Manual_Complete')) {
      throw new RefundService.RefundException(
        'You do not have permission to perform this refund operation'
      );
    }
    if (String.isBlank(externalReference) || externalReference.length() > 80) {
      throw new RefundService.RefundException(
        'Enter the external refund transaction reference.'
      );
    }
    if (
      refund == null ||
      request == null ||
      refund.Id == null ||
      request.Id == null ||
      refund.Return_Request__c != request.Id ||
      refund.Status__c != RefundDomain.Status.FAILED.name() ||
      refund.Manual_Completed_At__c != null ||
      request.Status__c != SmartReturnConstants.STATUS_REFUND_FAILED
    ) {
      throw new RefundService.RefundException(
        'Only a failed refund can be completed manually.'
      );
    }

    refund.Manual_Reference__c = externalReference;
    refund.Manual_Completed_At__c = System.now();
    refund.Manual_Completed_By__c = UserInfo.getUserId();
    RefundDomain.validateCompletion(
      request,
      refund,
      SmartReturnConstants.STATUS_COMPLETED
    );

    // Accounting's controlled action must not require general record edit access.
    StateTransitionService.transitionBulk(
      new List<TransitionRequest>{
        new TransitionRequest(
          request.Id,
          SmartReturnConstants.STATUS_COMPLETED,
          null
        )
      },
      true
    );
    update as system new Refund_Transaction__c(
      Id = refund.Id,
      Manual_Reference__c = refund.Manual_Reference__c,
      Manual_Completed_At__c = refund.Manual_Completed_At__c,
      Manual_Completed_By__c = refund.Manual_Completed_By__c
    );
    if (refund.Accounting_Task_Id__c != null) {
      update as system new Task(
        Id = (Id) refund.Accounting_Task_Id__c,
        Status = 'Completed'
      );
    }
  }
}
