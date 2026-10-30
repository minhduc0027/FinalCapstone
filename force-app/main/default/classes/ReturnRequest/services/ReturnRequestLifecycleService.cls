public inherited sharing class ReturnRequestLifecycleService {
  /** Receives goods without granting direct workflow-state editing to store users. */
  public static void receiveGoods(Id requestId, Datetime lastModifiedAt) {
    if (
      !FeatureManagement.checkPermission('Return_Receive_Goods') ||
      !Return_Request__c.SObjectType.getDescribe(
          SObjectDescribeOptions.DEFERRED
        )
        .isUpdateable()
    ) {
      throw new LifecycleException('Bạn không có quyền xác nhận nhận hàng.');
    }
    if (requestId == null || lastModifiedAt == null) {
      throw new LifecycleException(
        'Vui lòng tải lại yêu cầu trước khi xác nhận nhận hàng.'
      );
    }
    List<Return_Request__c> requests = ReturnRequestSelector.forGoodsReceipt(
      requestId
    );
    if (requests.isEmpty() || !requests[0].Is_My_Store__c) {
      throw new LifecycleException(
        'Chỉ có thể nhận hàng cho yêu cầu thuộc cửa hàng của bạn.'
      );
    }
    Return_Request__c request = requests[0];
    if (request.LastModifiedDate != lastModifiedAt) {
      throw new LifecycleException(
        Label.SmartReturn_MSG_13.replace('{0}', request.Name)
      );
    }
    if (request.Status__c != SmartReturnConstants.STATUS_AWAITING_GOODS) {
      throw new LifecycleException(
        'Không thể chuyển yêu cầu từ ' + request.Status__c + ' sang INSPECTING.'
      );
    }
    // The permission and store checks authorize this single field update; FLS stays read-only.
    update as system new Return_Request__c(
      Id = request.Id,
      Status__c = SmartReturnConstants.STATUS_INSPECTING
    );
  }

  public class LifecycleException extends Exception {
  }

  public static void beforeInsert(List<Return_Request__c> requests) {
    List<Return_Request__c> awaitingApproval = new List<Return_Request__c>();
    for (Return_Request__c request : requests) {
      validateRejectionReason(request);
      if (isAwaitingApproval(request.Status__c)) {
        markApprovalSubmitted(request);
        awaitingApproval.add(request);
      }
      if (request.Status__c == SmartReturnConstants.STATUS_AWAITING_GOODS) {
        request.Goods_Deadline__c = Date.today()
          .addDays(SmartReturnConfigService.getGoodsReturnWindowDays());
      }
    }
    assignApprovers(awaitingApproval);
  }

  public static void beforeUpdate(
    List<Return_Request__c> requests,
    Map<Id, Return_Request__c> previousById
  ) {
    List<Return_Request__c> awaitingApproval = new List<Return_Request__c>();
    for (Return_Request__c request : requests) {
      Return_Request__c previous = previousById.get(request.Id);
      validateRejectionReason(request);
      if (previous == null)
        continue;
      if (
        isAwaitingApproval(request.Status__c) &&
        (previous.Status__c != request.Status__c ||
        previous.Required_Approval_Level__c !=
        request.Required_Approval_Level__c ||
        previous.Store__c != request.Store__c)
      ) {
        awaitingApproval.add(request);
      }
      if (previous.Status__c == request.Status__c)
        continue;

      if (isAwaitingApproval(request.Status__c)) {
        markApprovalSubmitted(request);
        request.Decision_By__c = null;
        request.Decision_At__c = null;
      }

      if (
        isAwaitingApproval(previous.Status__c) &&
        (request.Status__c == SmartReturnConstants.STATUS_AWAITING_GOODS ||
        request.Status__c == SmartReturnConstants.STATUS_INSPECTING ||
        request.Status__c == SmartReturnConstants.STATUS_REJECTED)
      ) {
        request.Decision_By__c = UserInfo.getUserId();
        request.Decision_At__c = System.now();
      }

      if (request.Status__c == SmartReturnConstants.STATUS_AWAITING_GOODS) {
        request.Goods_Deadline__c = Date.today()
          .addDays(SmartReturnConfigService.getGoodsReturnWindowDays());
      }
    }
    assignApprovers(awaitingApproval);
  }

  private static Boolean isAwaitingApproval(String status) {
    return status == SmartReturnConstants.STATUS_PENDING_APPROVAL ||
      status == SmartReturnConstants.STATUS_RE_CONFIRMING;
  }

  private static void validateRejectionReason(Return_Request__c request) {
    if (
      request.Status__c == SmartReturnConstants.STATUS_REJECTED &&
      String.isBlank(request.Rejection_Reason__c)
    ) {
      request.Rejection_Reason__c.addError('Enter a rejection reason.');
    }
  }

  private static void markApprovalSubmitted(Return_Request__c request) {
    Datetime submittedAt = System.now();
    request.Approval_Submitted_At__c = submittedAt;
    request.Approval_Due_At__c = submittedAt.addHours(
      SmartReturnConfigService.getApprovalTimeoutHours()
    );
  }

  private static void assignApprovers(List<Return_Request__c> requests) {
    if (requests.isEmpty())
      return;

    Set<Id> storeIds = new Set<Id>();
    for (Return_Request__c request : requests)
      storeIds.add(request.Store__c);
    Map<Id, Store__c> stores = new Map<Id, Store__c>(
      [
        SELECT Id, Store_Manager__c, Region_Manager__c
        FROM Store__c
        WHERE Id IN :storeIds
        WITH SYSTEM_MODE
      ]
    );

    for (Return_Request__c request : requests) {
      Store__c store = stores.get(request.Store__c);
      if (store == null)
        continue;
      if (
        request.Required_Approval_Level__c ==
        SmartReturnConstants.APPROVAL_CHT &&
        store.Store_Manager__c == null
      ) {
        request.Required_Approval_Level__c = SmartReturnConstants.APPROVAL_QLV;
      }
      if (
        request.Required_Approval_Level__c == SmartReturnConstants.APPROVAL_CHT
      ) {
        request.ApproverId__c = store.Store_Manager__c;
      } else if (
        request.Required_Approval_Level__c == SmartReturnConstants.APPROVAL_QLV
      ) {
        request.ApproverId__c = store.Region_Manager__c;
      }
    }
  }
}
