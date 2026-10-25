public with sharing class RefundDomain {
  public enum Status {
    QUEUED,
    PROCESSING,
    PENDING,
    SUCCEEDED,
    FAILED
  }

  private static final Integer MIN_ATTEMPTS = 1;
  private static final Integer MAX_STORED_ATTEMPTS = 999;
  private static final Integer MIN_RETRY_INTERVAL_MINUTES = 15;
  private static final Integer MIN_PAYHUB_TIMEOUT_SECONDS = 1;
  private static final Integer MAX_PAYHUB_TIMEOUT_SECONDS = 120;
  private static final Integer NO_ATTEMPTS = 0;
  private static final Integer NO_PASSED_LINES = 0;
  private static final Decimal ZERO_VND = 0;
  private static final Integer VND_SCALE = 0;
  private static final Integer MAX_REFERENCE_LENGTH = 80;
  private static final Integer MAX_ERROR_CODE_LENGTH = 100;
  private static final Integer HTTP_OK = 200;
  private static final Integer HTTP_SERVER_ERROR_MIN = 500;

  private static final String PAYHUB_SUCCESS = 'SUCCESS';
  private static final String PAYHUB_PENDING = 'PENDING';
  private static final String PAYHUB_FAILED = 'FAILED';
  private static final String LOG_SUCCESS = 'SUCCESS';
  private static final String LOG_PENDING = 'PENDING';
  private static final String LOG_FAILED = 'FAILED';
  private static final String LOG_TIMEOUT = 'TIMEOUT';
  private static final String INSPECTION_PASSED = 'PASSED';
  private static final String INSPECTION_FAILED = 'FAILED';

  private static final String ERROR_OUTCOME_UNCERTAIN = 'OUTCOME_UNCERTAIN';
  private static final String ERROR_PROVIDER_UNAVAILABLE = 'PROVIDER_UNAVAILABLE';
  private static final String ERROR_PAYHUB_REJECTED = 'PAYHUB_REJECTED';
  private static final String ERROR_UNEXPECTED_RESPONSE = 'UNEXPECTED_RESPONSE';
  private static final String ERROR_REFUND_ID_MISMATCH = 'REFUND_ID_MISMATCH';
  private static final String ERROR_STALE_CALLBACK = 'STALE_CALLBACK';
  private static final String ERROR_DUPLICATE_CALLBACK = 'DUPLICATE_CALLBACK';
  private static final String ERROR_RECONCILIATION_REQUIRED = 'RECONCILIATION_REQUIRED';

  public class Policy {
    public Integer maxAttempts;
    public Integer intervalMinutes;

    public Policy(Integer maximum, Integer interval) {
      if (
        maximum == null ||
        maximum < MIN_ATTEMPTS ||
        maximum > MAX_STORED_ATTEMPTS ||
        interval == null ||
        interval < MIN_RETRY_INTERVAL_MINUTES
      ) {
        throw new RuleException(
          String.format(
            'Invalid policy: maxAttempts must be {0}-{1}, intervalMinutes must be >= {2}',
            new List<String>{
              String.valueOf(MIN_ATTEMPTS),
              String.valueOf(MAX_STORED_ATTEMPTS),
              String.valueOf(MIN_RETRY_INTERVAL_MINUTES)
            }
          )
        );
      }

      maxAttempts = maximum;
      intervalMinutes = interval;
    }
  }

  public static Integer timeoutMilliseconds(Integer seconds) {
    if (
      seconds == null ||
      seconds < MIN_PAYHUB_TIMEOUT_SECONDS ||
      seconds > MAX_PAYHUB_TIMEOUT_SECONDS
    ) {
      throw new RuleException(
        'PayHub timeout must be between 1 and 120 seconds.'
      );
    }
    return seconds * 1000;
  }

  public class Decision {
    public String status;
    public String logResult;
    public String errorCode;
    public Boolean retryable = false;
  }

  public static void validateInspection(
    Return_Request__c request,
    List<Return_Request_Line__c> lines
  ) {
    if (
      request == null ||
      request.Status__c != SmartReturnConstants.STATUS_INSPECTING ||
      request.Inspection_Completed_At__c == null ||
      lines == null ||
      lines.isEmpty()
    ) {
      throw new RuleException('Inspection not completed');
    }

    Integer passed = NO_PASSED_LINES;
    for (Return_Request_Line__c line : lines) {
      if (line.Inspection_Result__c == INSPECTION_PASSED) {
        passed++;
      } else if (line.Inspection_Result__c != INSPECTION_FAILED) {
        throw new RuleException(
          String.join(
            new List<String>{
              'Invalid inspection result:',
              line.Inspection_Result__c
            },
            ' '
          )
        );
      }
    }

    if (
      passed == NO_PASSED_LINES ||
      request.Actual_Refund_Amount__c == null ||
      request.Actual_Refund_Amount__c <= ZERO_VND ||
      request.Actual_Refund_Amount__c !=
      request.Actual_Refund_Amount__c.setScale(VND_SCALE) ||
      request.Order__c == null
    ) {
      throw new RuleException(
        'Inspection failed: no passed lines, invalid refund amount, or missing order reference'
      );
    }
  }

  public static Decision classify(PayHubClient.Result response) {
    Decision d = new Decision();
    d.status = Status.FAILED.name();
    d.logResult = LOG_FAILED;
    d.errorCode = response.errorCode;

    if (response.transportFailure) {
      d.retryable = true;
      d.logResult = LOG_TIMEOUT;
      d.errorCode = ERROR_OUTCOME_UNCERTAIN;
    } else if (
      response.httpStatus >= HTTP_SERVER_ERROR_MIN ||
      (response.httpStatus == HTTP_OK && response.invalidResponse)
    ) {
      d.retryable = true;
      d.errorCode = ERROR_PROVIDER_UNAVAILABLE;
    } else if (
      response.httpStatus == HTTP_OK &&
      response.refundId != null &&
      response.status == PAYHUB_SUCCESS
    ) {
      d.status = Status.SUCCEEDED.name();
      d.logResult = LOG_SUCCESS;
    } else if (
      response.httpStatus == HTTP_OK &&
      response.refundId != null &&
      response.status == PAYHUB_PENDING
    ) {
      d.status = Status.PENDING.name();
      d.logResult = LOG_PENDING;
    } else if (
      response.httpStatus == HTTP_OK &&
      response.status == PAYHUB_FAILED
    ) {
      d.errorCode = response.errorCode == null
        ? ERROR_PAYHUB_REJECTED
        : response.errorCode;
    } else if (d.errorCode == null) {
      d.retryable = response.httpStatus == HTTP_OK;
      d.errorCode = ERROR_UNEXPECTED_RESPONSE;
    }

    return d;
  }

  public static Boolean terminal(Refund_Transaction__c refund) {
    return refund.Status__c == Status.SUCCEEDED.name() ||
      refund.Status__c == Status.FAILED.name() ||
      refund.Status__c == Status.PENDING.name() ||
      refund.Manual_Completed_At__c != null;
  }

  public static Boolean canClaim(
    Refund_Transaction__c refund,
    Policy policy,
    Datetime nowValue
  ) {
    if (terminal(refund))
      return false;

    if (refund.Status__c == Status.PROCESSING.name()) {
      return refund.Last_Attempt_At__c != null &&
        refund.Last_Attempt_At__c.addMinutes(policy.intervalMinutes) <=
        nowValue;
    }

    return refund.Status__c == Status.QUEUED.name() &&
      (refund.Next_Retry_At__c == null ||
      refund.Next_Retry_At__c <= nowValue) &&
      (refund.Last_Attempt_At__c == null ||
      refund.Last_Attempt_At__c.addMinutes(policy.intervalMinutes) <= nowValue);
  }

  public static Boolean ownsClaim(
    Refund_Transaction__c refund,
    String jobId,
    Integer attempt
  ) {
    return refund.Status__c == Status.PROCESSING.name() &&
      refund.Worker_Job_Id__c == jobId &&
      refund.Attempt_Count__c == attempt &&
      refund.Manual_Completed_At__c == null;
  }

  public class Callback {
    public String refundId;
    public String merchantRef;
    public String status;
    public String failureReason;
    public Datetime processedAt;
  }

  public static void validateCallback(Callback callback) {
    if (
      callback == null ||
      PayHubClient.safeCode(callback.refundId, MAX_REFERENCE_LENGTH) == null ||
      PayHubClient.safeCode(callback.merchantRef, MAX_REFERENCE_LENGTH) ==
      null ||
      callback.processedAt == null ||
      (callback.status != PAYHUB_SUCCESS &&
      callback.status != PAYHUB_FAILED) ||
      (callback.failureReason != null &&
      PayHubClient.safeCode(callback.failureReason, MAX_ERROR_CODE_LENGTH) ==
      null)
    ) {
      throw new RuleException('Invalid callback data');
    }
  }

  public static String callbackDisposition(
    Refund_Transaction__c row,
    Callback callback
  ) {
    if (
      row.PayHub_Refund_Id__c != null &&
      row.PayHub_Refund_Id__c != callback.refundId
    ) {
      return ERROR_REFUND_ID_MISMATCH;
    }
    if (
      row.Provider_Processed_At__c != null &&
      callback.processedAt < row.Provider_Processed_At__c
    ) {
      return ERROR_STALE_CALLBACK;
    }
    if (
      row.Status__c == Status.SUCCEEDED.name() ||
      row.Status__c == Status.FAILED.name() ||
      row.Manual_Completed_At__c != null
    ) {
      Boolean sameOutcome =
        (row.Status__c == Status.SUCCEEDED.name() &&
        callback.status == PAYHUB_SUCCESS) ||
        (row.Status__c == Status.FAILED.name() &&
        callback.status == PAYHUB_FAILED);
      return sameOutcome
        ? ERROR_DUPLICATE_CALLBACK
        : ERROR_RECONCILIATION_REQUIRED;
    }
    if (
      row.Status__c == Status.PENDING.name() ||
      row.Status__c == Status.PROCESSING.name() ||
      (row.Status__c == Status.QUEUED.name() &&
      row.Attempt_Count__c > NO_ATTEMPTS)
    ) {
      return null;
    }
    return ERROR_RECONCILIATION_REQUIRED;
  }

  public static void validateCompletion(
    Return_Request__c request,
    Refund_Transaction__c refund,
    String target
  ) {
    String expected = refund.Manual_Completed_At__c == null
      ? SmartReturnConstants.STATUS_REFUND_PROCESSING
      : SmartReturnConstants.STATUS_REFUND_FAILED;
    if (
      request == null ||
      request.Status__c != expected ||
      (target != SmartReturnConstants.STATUS_COMPLETED &&
      target != SmartReturnConstants.STATUS_REFUND_FAILED)
    ) {
      throw new RuleException(
        'Request status is not valid for completion, please check the request status and target status'
      );
    }
  }

  public class RuleException extends Exception {
  }
}
