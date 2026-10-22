public inherited sharing class StateTransitionService {
  public static final String STATUS_NEW = 'New';
  public static final String STATUS_PENDING_APPROVAL = 'Pending Approval';
  public static final String STATUS_AWAITING_GOODS = 'Awaiting Goods';
  public static final String STATUS_INSPECTING = 'Inspecting';
  public static final String STATUS_REFUND_PROCESSING = 'Refund Processing';
  public static final String STATUS_COMPLETED = 'Completed';
  public static final String STATUS_REFUND_FAILED = 'Refund Failed';
  public static final String STATUS_REJECTED = 'Rejected';
  public static final String STATUS_CANCELLED = 'Cancelled';

  /*
   * Lưu note tạm thời trong transaction.
   * Trigger handler sẽ lấy note này để tạo history.
   */
  private static Map<Id, String> transitionNotesByCaseId = new Map<Id, String>();

  public static void transition(Id caseId, String targetStatus, String note) {
    if (caseId == null) {
      throw new StateTransitionException(
        'Return Request Id không được để trống.'
      );
    }

    List<Case> requests = [
      SELECT Id, Status
      FROM Case
      WHERE Id = :caseId
      LIMIT 1
      FOR UPDATE
    ];

    if (requests.isEmpty()) {
      throw new StateTransitionException('Không tìm thấy yêu cầu đổi trả.');
    }

    Case requestRecord = requests[0];

    try {
      StateTransitionValidator.validate(requestRecord.Status, targetStatus);
    } catch (StateTransitionValidator.StateTransitionException ex) {
      /*
       * Giữ abstraction của service:
       * caller chỉ cần xử lý exception của service.
       */
      throw new StateTransitionException(ex.getMessage());
    }

    if (requestRecord.Status == targetStatus) {
      return;
    }

    transitionNotesByCaseId.put(requestRecord.Id, note);

    requestRecord.Status = targetStatus;

    try {
      update requestRecord;
      //Log trace
      LogService.info(
        requestRecord,
        'Status updated from ' + requestRecord.Status + ' to ' + targetStatus,
        'StateTransitionService',
        'UPDATE'
      );
      LogService.insertLogs();
    } catch (DmlException ex) {
      throw new StateTransitionException(
        'Không thể cập nhật trạng thái yêu cầu: ' + ex.getMessage()
      );
    } finally {
      transitionNotesByCaseId.remove(requestRecord.Id);
    }
  }

  public static List<TransitionResult> transitionBulk(
    Map<Id, TransitionRequest> requestsByCaseId
  ) {
    List<TransitionResult> results = new List<TransitionResult>();

    if (requestsByCaseId == null || requestsByCaseId.isEmpty()) {
      return results;
    }

    Map<Id, Case> casesById = new Map<Id, Case>(
      [
        SELECT Id, CaseNumber, Status
        FROM Case
        WHERE Id IN :requestsByCaseId.keySet()
        FOR UPDATE
      ]
    );

    List<Case> casesToUpdate = new List<Case>();

    for (Id caseId : requestsByCaseId.keySet()) {
      TransitionRequest request = requestsByCaseId.get(caseId);

      Case requestRecord = casesById.get(caseId);

      if (requestRecord == null) {
        results.add(
          new TransitionResult(
            caseId,
            false,
            null,
            'Không tìm thấy yêu cầu đổi trả.'
          )
        );
        continue;
      }

      if (request == null) {
        results.add(
          new TransitionResult(
            caseId,
            false,
            requestRecord.Status,
            'Transition request không được để trống.'
          )
        );
        continue;
      }

      try {
        StateTransitionValidator.validate(
          requestRecord.Status,
          request.targetStatus
        );

        if (requestRecord.Status == request.targetStatus) {
          results.add(
            new TransitionResult(caseId, true, requestRecord.Status, null)
          );
          continue;
        }

        transitionNotesByCaseId.put(caseId, request.note);

        requestRecord.Status = request.targetStatus;
        casesToUpdate.add(requestRecord);
      } catch (Exception ex) {
        results.add(
          new TransitionResult(
            caseId,
            false,
            requestRecord.Status,
            ex.getMessage()
          )
        );
      }
    }

    if (!casesToUpdate.isEmpty()) {
      Database.SaveResult[] saveResults = Database.update(casesToUpdate, false);

      for (Integer index = 0; index < saveResults.size(); index++) {
        Case requestRecord = casesToUpdate[index];
        Database.SaveResult saveResult = saveResults[index];

        if (saveResult.isSuccess()) {
          results.add(
            new TransitionResult(
              requestRecord.Id,
              true,
              requestRecord.Status,
              null
            )
          );
        } else {
          results.add(
            new TransitionResult(
              requestRecord.Id,
              false,
              requestRecord.Status,
              joinErrors(saveResult.getErrors())
            )
          );
        }
      }
    }

    transitionNotesByCaseId.clear();

    return results;
  }

  public static String getTransitionNote(Id caseId) {
    return transitionNotesByCaseId.get(caseId);
  }

  private static String joinErrors(Database.Error[] errors) {
    List<String> messages = new List<String>();

    for (Database.Error error : errors) {
      messages.add(error.getMessage());
    }

    return String.join(messages, '; ');
  }

  public class TransitionRequest {
    public String targetStatus;
    public String note;

    public TransitionRequest(String targetStatus, String note) {
      this.targetStatus = targetStatus;
      this.note = note;
    }
  }

  public class TransitionResult {
    public Id caseId;
    public Boolean success;
    public String status;
    public String errorMessage;

    public TransitionResult(
      Id caseId,
      Boolean success,
      String status,
      String errorMessage
    ) {
      this.caseId = caseId;
      this.success = success;
      this.status = status;
      this.errorMessage = errorMessage;
    }
  }

  public class StateTransitionException extends Exception {
  }
}
