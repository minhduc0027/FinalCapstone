public with sharing class RefundService {
  private static final Integer REFUNDS_PER_WORKER = 10;
  @TestVisible
  private static Integer eventsPublished = 0;
  @TestVisible
  private static Integer notificationsSent = 0;
  @TestVisible
  private static Integer notificationEventsQueued = 0;

  private static void requirePermission(String name) {
    if (!FeatureManagement.checkPermission(name)) {
      throw new RefundException(
        'You do not have permission to perform this refund operation'
      );
    }
  }

  private static RefundDomain.Policy policy() {
    return new RefundDomain.Policy(
      SmartReturnConfigService.getPayHubMaxRetries(),
      SmartReturnConfigService.getPayHubRetryInterval()
    );
  }

  // TODO: [INCOMPLETE]: Inspection must finalize and call startRefund while status is INSPECTING.
  public static Id startRefund(Id requestId) {
    if (requestId == null) {
      throw new RefundException('Request Code cannot be blank');
    }
    return startRefunds(new Set<Id>{ requestId }, false).get(requestId);
  }

  private static Map<Id, Id> startRefunds(Set<Id> ids, Boolean skipInvalid) {
    requirePermission('Refund_Process');
    Map<Id, Id> result = new Map<Id, Id>();
    if (
      !SmartReturnConfigService.isFeatureEnabled('Send_PayHub') || ids.isEmpty()
    ) {
      return result;
    }

    Map<Id, Return_Request__c> requests = ReturnRequestSelector.byIds(
      ids,
      true
    );
    Map<Id, Refund_Transaction__c> existing = new Map<Id, Refund_Transaction__c>();
    for (Refund_Transaction__c row : RefundSelector.forRequests(ids)) {
      existing.put(row.Return_Request__c, row);
    }
    Map<Id, List<Return_Request_Line__c>> lines = new Map<Id, List<Return_Request_Line__c>>();
    for (Return_Request_Line__c line : ReturnRequestSelector.lines(ids)) {
      if (!lines.containsKey(line.Return_Request__c)) {
        lines.put(line.Return_Request__c, new List<Return_Request_Line__c>());
      }
      lines.get(line.Return_Request__c).add(line);
    }

    List<Refund_Transaction__c> inserts = new List<Refund_Transaction__c>();
    List<TransitionRequest> requestUpdates = new List<TransitionRequest>();
    for (Id requestId : ids) {
      if (existing.containsKey(requestId)) {
        result.put(requestId, existing.get(requestId).Id);
        continue;
      }

      Return_Request__c request = requests.get(requestId);
      try {
        RefundDomain.validateInspection(request, lines.get(requestId));
      } catch (RefundDomain.RuleException e) {
        if (skipInvalid) {
          continue;
        }
        throw e;
      }

      inserts.add(
        new Refund_Transaction__c(
          Return_Request__c = request.Id,
          Merchant_Reference__c = request.Name,
          Idempotency_Key__c = request.Name,
          Order_Number__c = request.Order__r.OrderNumber,
          Refund_Amount__c = request.Actual_Refund_Amount__c,
          Status__c = RefundDomain.Status.QUEUED.name(),
          Attempt_Count__c = 0
        )
      );

      requestUpdates.add(
        new TransitionRequest(
          request.Id,
          SmartReturnConstants.STATUS_REFUND_PROCESSING,
          null
        )
      );
    }

    Savepoint checkpoint = Database.setSavepoint();
    try {
      if (!inserts.isEmpty()) {
        insert as user inserts;
        for (Refund_Transaction__c row : inserts) {
          result.put(row.Return_Request__c, row.Id);
        }

        StateTransitionService.transitionBulk(requestUpdates, true);
      }

      claimRefunds(new Set<Id>(result.values()));
    } catch (Exception e) {
      Database.rollback(checkpoint);
      throw new RefundException(
        String.join(
          new List<String>{ 'Cannot start refund:', e.getMessage() },
          ' '
        ),
        e
      );
    }
    return result;
  }

  public static void claimRefunds(Set<Id> ids) {
    requirePermission('Refund_Process');
    if (
      !SmartReturnConfigService.isFeatureEnabled('Send_PayHub') || ids.isEmpty()
    ) {
      return;
    }
    RefundDomain.Policy current = policy();
    List<Refund_Transaction__c> snapshots = RefundSelector.byIds(ids, false);
    Set<Id> parents = new Set<Id>();
    for (Refund_Transaction__c row : snapshots) {
      parents.add(row.Return_Request__c);
    }
    Map<Id, Return_Request__c> requests = ReturnRequestSelector.byIds(
      parents,
      true
    );

    List<Refund_Transaction__c> refunds = RefundSelector.byIds(ids, true);
    List<Refund_Transaction__c> updates = new List<Refund_Transaction__c>();
    List<Refund_Transaction__c> exhausted = new List<Refund_Transaction__c>();
    List<Integration_Log__c> expiredExchanges = new List<Integration_Log__c>();
    Integer room =
      REFUNDS_PER_WORKER *
      (Limits.getLimitQueueableJobs() - Limits.getQueueableJobs());
    List<Refund_Transaction__c> toSend = new List<Refund_Transaction__c>();
    Datetime nowValue = System.now();

    Savepoint checkpoint = Database.setSavepoint();
    try {
      for (Refund_Transaction__c row : refunds) {
        if (room <= 0) {
          break;
        }
        if (!RefundDomain.canClaim(row, current, nowValue)) {
          continue;
        }
        Return_Request__c request = requests.get(row.Return_Request__c);
        if (
          request == null ||
          request.Status__c != SmartReturnConstants.STATUS_REFUND_PROCESSING
        ) {
          continue;
        }
        if (row.Status__c == RefundDomain.Status.PROCESSING.name()) {
          expiredExchanges.add(
            IntegrationLogService.outboundEntry(
              row,
              'TIMEOUT',
              'ABANDONED_WORKER',
              null
            )
          );
        }

        if (row.Attempt_Count__c >= current.maxAttempts) {
          row.Status__c = RefundDomain.Status.FAILED.name();
          row.Last_Error_Code__c = 'RETRY_EXHAUSTED';
          row.Worker_Job_Id__c = null;
          row.Next_Retry_At__c = null;
          exhausted.add(row);
        } else {
          PayHubClient.configuredTimeoutMs();
          row.Status__c = RefundDomain.Status.PROCESSING.name();
          row.Attempt_Count__c++;
          row.Last_Attempt_At__c = nowValue;
          row.Next_Retry_At__c = null;
          toSend.add(row);
          room--;
        }
        updates.add(row);
      }

      for (
        Integer offset = 0; offset < toSend.size(); offset += REFUNDS_PER_WORKER
      ) {
        List<Id> workerIds = new List<Id>();
        Integer endIndex = Math.min(offset + REFUNDS_PER_WORKER, toSend.size());
        for (Integer i = offset; i < endIndex; i++) {
          workerIds.add(toSend[i].Id);
        }
        String workerId = System.enqueueJob(new RefundQueueable(workerIds));
        for (Integer i = offset; i < endIndex; i++) {
          toSend[i].Worker_Job_Id__c = workerId;
        }
      }

      IntegrationLogService.recordAll(expiredExchanges);
      if (!exhausted.isEmpty()) {
        finishAll(
          exhausted,
          requests,
          SmartReturnConstants.STATUS_REFUND_FAILED
        );
      }
      if (!updates.isEmpty()) {
        update as user updates;
      }
    } catch (Exception e) {
      Database.rollback(checkpoint);
      throw e;
    }
  }

  public static void processClaimed(Id refundId, String jobId) {
    processClaimed(new Set<Id>{ refundId }, jobId);
  }

  public static void processClaimed(Set<Id> refundIds, String jobId) {
    requirePermission('Refund_Process');
    List<Refund_Transaction__c> snapshots = RefundSelector.byIds(
      refundIds,
      false
    );
    if (snapshots.isEmpty()) {
      return;
    }
    if (!SmartReturnConfigService.isFeatureEnabled('Send_PayHub')) {
      for (Refund_Transaction__c sent : snapshots) {
        releaseUnsentClaim(sent, jobId, sent.Attempt_Count__c.intValue());
      }
      return;
    }

    try {
      PayHubClient.configuredTimeoutMs();
    } catch (PayHubClient.ConfigurationException e) {
      for (Refund_Transaction__c sent : snapshots) {
        releaseUnsentClaim(sent, jobId, sent.Attempt_Count__c.intValue());
      }
      LogService.error(e, 'RefundService', 'processClaimed');
      LogService.insertLogs();
      return;
    }

    Map<Id, PayHubClient.Result> responses = new Map<Id, PayHubClient.Result>();
    for (Refund_Transaction__c sent : snapshots) {
      if (
        !RefundDomain.ownsClaim(sent, jobId, sent.Attempt_Count__c.intValue())
      ) {
        continue;
      }
      responses.put(
        sent.Id,
        PayHubClient.send(
          sent.Merchant_Reference__c,
          sent.Order_Number__c,
          sent.Refund_Amount__c,
          sent.Idempotency_Key__c
        )
      );
    }
    for (Refund_Transaction__c sent : snapshots) {
      if (responses.containsKey(sent.Id)) {
        persistResponse(
          sent,
          jobId,
          sent.Attempt_Count__c.intValue(),
          responses.get(sent.Id)
        );
      }
    }
  }

  private static void releaseUnsentClaim(
    Refund_Transaction__c sent,
    String jobId,
    Integer attempt
  ) {
    ReturnRequestSelector.byIds(new Set<Id>{ sent.Return_Request__c }, true);
    Refund_Transaction__c row = RefundSelector.byIds(
      new Set<Id>{ sent.Id },
      true
    )[0];

    if (RefundDomain.ownsClaim(row, jobId, attempt)) {
      row.Status__c = RefundDomain.Status.QUEUED.name();
      row.Worker_Job_Id__c = null;
      row.Attempt_Count__c--;
      row.Next_Retry_At__c = System.now().addMinutes(policy().intervalMinutes);
      update as user row;
    }
  }

  @TestVisible
  private static void persistResponse(
    Refund_Transaction__c sent,
    String jobId,
    Integer attempt,
    PayHubClient.Result response
  ) {
    Map<Id, Return_Request__c> requests = ReturnRequestSelector.byIds(
      new Set<Id>{ sent.Return_Request__c },
      true
    );
    Refund_Transaction__c row = RefundSelector.byIds(
      new Set<Id>{ sent.Id },
      true
    )[0];
    RefundDomain.Decision decision = RefundDomain.classify(response);

    Boolean ownsClaim = RefundDomain.ownsClaim(row, jobId, attempt);
    RefundDomain.Policy current = policy();
    Savepoint checkpoint = Database.setSavepoint();
    try {
      IntegrationLogService.recordOutbound(
        sent,
        decision.logResult,
        ownsClaim ? decision.errorCode : 'STALE_WORKER',
        response
      );
      if (!ownsClaim) {
        return;
      }
      row.Worker_Job_Id__c = null;
      row.Last_Attempt_At__c = response.occurredAt;
      if (response.refundId != null) {
        row.PayHub_Refund_Id__c = response.refundId;
      }
      row.Last_Error_Code__c = decision.errorCode;
      row.Last_Error_Message__c = decision.errorCode;
      if (decision.retryable && row.Attempt_Count__c < current.maxAttempts) {
        row.Status__c = RefundDomain.Status.QUEUED.name();
        row.Next_Retry_At__c = response.occurredAt.addMinutes(
          current.intervalMinutes
        );
      } else {
        row.Status__c = decision.status;
        row.Next_Retry_At__c = null;
        if (row.Status__c == RefundDomain.Status.SUCCEEDED.name()) {
          row.Completed_At__c = System.now();
          finish(
            row,
            requests.get(row.Return_Request__c),
            SmartReturnConstants.STATUS_COMPLETED
          );
        } else if (row.Status__c == RefundDomain.Status.FAILED.name()) {
          finish(
            row,
            requests.get(row.Return_Request__c),
            SmartReturnConstants.STATUS_REFUND_FAILED
          );
        }
      }
      update as user row;
    } catch (Exception e) {
      Database.rollback(checkpoint);
      IntegrationLogService.recordOutbound(
        sent,
        'FAILED',
        'PERSISTENCE_FAILED',
        response
      );
      LogService.error(
        'Could not persist the refund outcome; reconcile using the idempotency key.',
        'RefundService',
        'persistResponse'
      );
      LogService.insertLogs();
    }
  }

  public static void dispatchDue() {
    requirePermission('Refund_Process');
    if (!SmartReturnConfigService.isFeatureEnabled('Send_PayHub')) {
      return;
    }

    RefundDomain.Policy current = policy();
    Integer room = Math.min(
      25,
      REFUNDS_PER_WORKER *
      (Limits.getLimitQueueableJobs() - Limits.getQueueableJobs())
    );
    if (room <= 0) {
      return;
    }
    Set<Id> ids = new Map<Id, Refund_Transaction__c>(
        RefundSelector.due(System.now(), current.intervalMinutes, room)
      )
      .keySet();
    claimRefunds(ids);
    room = Math.min(
      25,
      REFUNDS_PER_WORKER *
      (Limits.getLimitQueueableJobs() - Limits.getQueueableJobs())
    );
    if (room > 0) {
      Set<Id> waitingIds = new Map<Id, Return_Request__c>(
          ReturnRequestSelector.waitingForRefund(room)
        )
        .keySet();
      startRefunds(waitingIds, true);
    }
  }

  public static Integer handleCallback(RefundDomain.Callback callback) {
    requirePermission('Refund_Callback');
    RefundDomain.validateCallback(callback);
    List<Refund_Transaction__c> found = RefundSelector.byMerchant(
      callback.merchantRef,
      false
    );
    if (found.isEmpty()) {
      IntegrationLogService.recordCallback(null, callback, 'UNKNOWN_MERCHANT');
      return 404;
    }
    Map<Id, Return_Request__c> requests = ReturnRequestSelector.byIds(
      new Set<Id>{ found[0].Return_Request__c },
      true
    );
    Refund_Transaction__c row = RefundSelector.byMerchant(
      callback.merchantRef,
      true
    )[0];
    Boolean success = callback.status == 'SUCCESS';
    String ignored = RefundDomain.callbackDisposition(row, callback);

    Savepoint checkpoint = Database.setSavepoint();
    try {
      IntegrationLogService.recordCallback(row, callback, ignored);
      if (ignored != null) {
        return 200;
      }
      row.Provider_Processed_At__c = callback.processedAt;
      row.PayHub_Refund_Id__c = callback.refundId;
      row.Status__c = success
        ? RefundDomain.Status.SUCCEEDED.name()
        : RefundDomain.Status.FAILED.name();
      row.Last_Error_Code__c = success ? null : callback.failureReason;
      row.Last_Error_Message__c = row.Last_Error_Code__c;
      row.Worker_Job_Id__c = null;
      row.Next_Retry_At__c = null;
      if (success) {
        row.Completed_At__c = System.now();
      }

      finish(
        row,
        requests.get(row.Return_Request__c),
        success
          ? SmartReturnConstants.STATUS_COMPLETED
          : SmartReturnConstants.STATUS_REFUND_FAILED
      );
      update as user row;
      return 200;
    } catch (Exception e) {
      Database.rollback(checkpoint);
      IntegrationLogService.recordCallback(row, callback, 'PERSISTENCE_FAILED');
      return 503;
    }
  }

  private static void finish(
    Refund_Transaction__c row,
    Return_Request__c request,
    String status
  ) {
    if (request == null) {
      throw new RefundException('Return request not found.');
    }
    finishAll(
      new List<Refund_Transaction__c>{ row },
      new Map<Id, Return_Request__c>{ request.Id => request },
      status
    );
  }

  private static void finishAll(
    List<Refund_Transaction__c> refunds,
    Map<Id, Return_Request__c> requests,
    String status
  ) {
    List<TransitionRequest> requestUpdates = new List<TransitionRequest>();
    List<Task> tasks = new List<Task>();
    List<Refund_Transaction__c> taskRefunds = new List<Refund_Transaction__c>();
    for (Refund_Transaction__c row : refunds) {
      Return_Request__c request = requests.get(row.Return_Request__c);
      RefundDomain.validateCompletion(request, row, status);
      requestUpdates.add(new TransitionRequest(request.Id, status, null));
      if (
        status == SmartReturnConstants.STATUS_REFUND_FAILED &&
        row.Accounting_Task_Id__c == null
      ) {
        tasks.add(
          new Task(
            WhatId = row.Id,
            Subject = 'SmartReturn: reconcile failed refund',
            Status = 'Not Started',
            Priority = 'High',
            Description = String.join(
              new List<String>{
                row.Merchant_Reference__c,
                row.Last_Error_Code__c == null
                  ? 'PAYHUB_FAILED'
                  : row.Last_Error_Code__c,
                'Reconcile the payment before manual completion; do not issue another refund.'
              },
              ' | '
            )
          )
        );
        taskRefunds.add(row);
      }
    }

    StateTransitionService.transitionBulk(requestUpdates, true);
    if (!tasks.isEmpty()) {
      Id owner = RefundSelector.accountingQueue();
      for (Task task : tasks) {
        task.OwnerId = owner;
      }
      insert as user tasks;
      for (Integer i = 0; i < tasks.size(); i++) {
        taskRefunds[i].Accounting_Task_Id__c = tasks[i].Id;
      }
    }
    notifyOutcomes(refunds, requests, status);
  }

  private static void notifyOutcomes(
    List<Refund_Transaction__c> refunds,
    Map<Id, Return_Request__c> requests,
    String status
  ) {
    publishManagerNotifications(refunds, status);
    if (!SmartReturnConfigService.isFeatureEnabled('Notify_POS_App')) {
      return;
    }
    List<Refund_Outcome__e> events = new List<Refund_Outcome__e>();
    for (Refund_Transaction__c row : refunds) {
      Return_Request__c request = requests.get(row.Return_Request__c);
      events.add(
        new Refund_Outcome__e(
          Request_Number__c = row.Merchant_Reference__c,
          Refund_Amount__c = row.Refund_Amount__c,
          Outcome__c = status,
          Store_Code__c = request.Store__c == null
            ? null
            : request.Store__r.Store_Code__c,
          Occurred_At__c = System.now()
        )
      );
    }
    for (Database.SaveResult published : EventBus.publish(events)) {
      if (!published.isSuccess()) {
        throw new RefundException('Could not record the refund notification.');
      }
    }
    eventsPublished += events.size();
  }

  @AuraEnabled
  public static void manualComplete(Id refundId, String externalReference) {
    requirePermission('Refund_Manual_Complete');
    if (String.isBlank(externalReference) || externalReference.length() > 80) {
      throw new RefundException(
        'Enter the external refund transaction reference.'
      );
    }
    List<Refund_Transaction__c> found = RefundSelector.byIds(
      new Set<Id>{ refundId },
      false
    );
    if (found.isEmpty()) {
      throw new RefundException('Refund transaction not found.');
    }
    Map<Id, Return_Request__c> requests = ReturnRequestSelector.byIds(
      new Set<Id>{ found[0].Return_Request__c },
      true
    );
    Refund_Transaction__c row = RefundSelector.byIds(
      new Set<Id>{ refundId },
      true
    )[0];
    if (
      row.Manual_Completed_At__c != null &&
      row.Manual_Reference__c == externalReference
    ) {
      return;
    }
    if (
      row.Status__c != RefundDomain.Status.FAILED.name() ||
      requests.get(row.Return_Request__c).Status__c !=
      SmartReturnConstants.STATUS_REFUND_FAILED
    ) {
      throw new RefundException(
        'Only a failed refund can be completed manually.'
      );
    }

    Savepoint checkpoint = Database.setSavepoint();
    try {
      row.Manual_Reference__c = externalReference;
      row.Manual_Completed_At__c = System.now();
      row.Manual_Completed_By__c = UserInfo.getUserId();
      finish(
        row,
        requests.get(row.Return_Request__c),
        SmartReturnConstants.STATUS_COMPLETED
      );
      update as system row;
      if (row.Accounting_Task_Id__c != null) {
        List<Task> tasks = RefundSelector.tasks(
          new Set<Id>{ (Id) row.Accounting_Task_Id__c }
        );
        for (Task task : tasks) {
          task.Status = 'Completed';
        }
        update as system tasks;
      }
    } catch (Exception e) {
      Database.rollback(checkpoint);
      throw new RefundException(
        'Could not record manual completion. Check the refund status and your permissions.',
        e
      );
    }
  }

  @TestVisible
  private static void publishManagerNotifications(
    List<Refund_Transaction__c> refunds,
    String outcome
  ) {
    List<Refund_Notification__e> events = new List<Refund_Notification__e>();
    for (Refund_Transaction__c refund : refunds) {
      events.add(
        new Refund_Notification__e(
          Request_Id__c = refund.Return_Request__c,
          Outcome__c = outcome
        )
      );
    }
    for (Database.SaveResult result : EventBus.publish(events)) {
      if (!result.isSuccess()) {
        throw new RefundException(
          'Could not queue the store manager notification.'
        );
      }
    }
    notificationEventsQueued += events.size();
  }

  public static void notifyStoreManagers(List<Refund_Notification__e> events) {
    if (events == null || events.isEmpty())
      return;

    Map<String, Refund_Notification__e> outcomes = new Map<String, Refund_Notification__e>();
    Set<Id> requestIds = new Set<Id>();
    for (Refund_Notification__e outcome : events) {
      if (
        outcome.Outcome__c != SmartReturnConstants.STATUS_COMPLETED &&
        outcome.Outcome__c != SmartReturnConstants.STATUS_REFUND_FAILED
      )
        continue;
      Id requestId = Id.valueOf(outcome.Request_Id__c);
      requestIds.add(requestId);
      outcomes.put(
        String.valueOf(requestId) + ':' + outcome.Outcome__c,
        outcome
      );
    }
    if (requestIds.isEmpty())
      return;

    Map<Id, Return_Request__c> requests = RefundNotificationSelector.requests(
      requestIds
    );
    Id typeId = RefundNotificationSelector.notificationTypeId();
    for (Refund_Notification__e outcome : outcomes.values()) {
      Return_Request__c request = requests.get(
        Id.valueOf(outcome.Request_Id__c)
      );
      if (request == null)
        continue;
      if (
        request.Store__r?.Store_Manager__c == null ||
        request.Store__r.Store_Manager__r.IsActive != true
      ) {
        LogService.warn(
          new List<SObject>{ request },
          'Refund notification skipped: the store has no active manager.',
          'RefundService',
          'notifyStoreManagers'
        );
        continue;
      }

      Boolean completed =
        outcome.Outcome__c == SmartReturnConstants.STATUS_COMPLETED;
      Messaging.CustomNotification notification = new Messaging.CustomNotification();
      notification.setNotificationTypeId(typeId);
      notification.setTargetId(request.Id);
      notification.setTitle(
        completed ? 'Hoàn tiền thành công' : 'Hoàn tiền thất bại'
      );
      notification.setBody(
        'Yêu cầu ' +
          request.Name +
          (completed
            ? ' đã hoàn tiền thành công.'
            : ' hoàn tiền thất bại. Kế toán cần đối soát.')
      );
      try {
        notification.send(
          new Set<String>{ String.valueOf(request.Store__r.Store_Manager__c) }
        );
        notificationsSent++;
      } catch (Exception error) {
        LogService.error(
          new List<SObject>{ request },
          error,
          'RefundService',
          'notifyStoreManagers'
        );
      }
    }
    LogService.insertLogs();
  }

  public class RefundException extends Exception {
  }
}
