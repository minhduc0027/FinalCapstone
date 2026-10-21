public with sharing class LogService {
  public enum LogLevel {
    INFO,
    WARN,
    ERROR,
    CRITICAL
  }

  /*
   * Internal transport model.
   *
   * This model is independent from Application_Log__c,
   * allowing the persistence implementation to be replaced
   * without changing the public logging methods.
   */
  public class LogEntry {
    public LogLevel level;
    public String message;
    public String source;
    public String operation;
    public Id relatedRecordId;
    public String transactionId;
    public Id userId;
    public String stackTrace;
    public Datetime loggedAt;
    public String eventKey;

    public LogEntry(
      LogLevel level,
      String message,
      String source,
      String operation,
      Id relatedRecordId,
      String stackTrace
    ) {
      this.level = level;
      this.message = message;
      this.source = source;
      this.operation = operation;
      this.relatedRecordId = relatedRecordId;
      this.transactionId = LogService.getTransactionId();
      this.userId = UserInfo.getUserId();
      this.stackTrace = stackTrace;
      this.loggedAt = Datetime.now();
      this.eventKey = System.UUID.randomUUID().toString();
    }
  }

  /*
   * Abstraction for log persistence.
   */
  public interface LogSink {
    List<Database.SaveResult> save(List<LogEntry> entries);
  }

  /*
   * Current persistence implementation.
   */
  private class PlatformEventLogSink implements LogSink {
    public List<Database.SaveResult> save(List<LogEntry> entries) {
      List<Application_Log_Event__e> events = new List<Application_Log_Event__e>();

      for (LogEntry entry : entries) {
        events.add(
          new Application_Log_Event__e(
            Level__c = entry.level.name(),
            Message__c = truncate(entry.message, 32768),
            Source__c = truncate(entry.source, 255),
            Operation__c = truncate(entry.operation, 100),
            RelatedRecord__c = entry.relatedRecordId,
            Transaction_Id__c = entry.transactionId,
            UserId__c = entry.userId,
            Stack_Trace__c = truncate(entry.stackTrace, 65536),
            Event_Key__c = entry.eventKey,
            Logged_At__c = entry.loggedAt
          )
        );
      }

      if (events.isEmpty()) {
        return new List<Database.SaveResult>();
      }
      return EventBus.publish(events);
    }

    private String truncate(String value, Integer maximumLength) {
      if (value == null) {
        return null;
      }

      if (value.length() <= maximumLength) {
        return value;
      }

      return value.substring(0, maximumLength);
    }
  }

  /*
   * Persistence implementation.
   */
  @TestVisible
  private static LogSink sink = new PlatformEventLogSink();
  /*
   * Transaction-level log buffer.
   *
   * Logging methods only add entries to this list.
   * They never perform DML.
   */
  @TestVisible
  private static List<LogEntry> logBuffer = new List<LogEntry>();

  /*
   * Adds INFO logs to the buffer.
   */
  public static void info(
    List<SObject> records,
    String message,
    String source,
    String operation
  ) {
    addLogs(records, LogLevel.INFO, message, source, operation, '');
  }

  /*
   * Adds WARN logs to the buffer.
   */
  public static void warn(
    List<SObject> records,
    String message,
    String source,
    String operation
  ) {
    addLogs(records, LogLevel.WARN, message, source, operation, '');
  }

  /*
   * Adds ERROR logs to the buffer.
   */
  public static void error(
    List<SObject> records,
    String message,
    String source,
    String operation
  ) {
    addLogs(records, LogLevel.ERROR, message, source, operation, '');
  }

  public static void error(
    List<SObject> records,
    Exception exceptionValue,
    String source,
    String operation
  ) {
    if (exceptionValue == null) {
      throw new LogServiceException('Exception must not be null.');
    }
    addLogs(
      records,
      LogLevel.ERROR,
      exceptionValue.getMessage(),
      source,
      operation,
      exceptionValue.getStackTraceString()
    );
  }

  /*
   * Adds CRITICAL logs to the buffer.
   */
  public static void critical(
    List<SObject> records,
    String message,
    String source,
    String operation
  ) {
    addLogs(records, LogLevel.CRITICAL, message, source, operation, '');
  }

  public static void info(String message, String source, String operation) {
    addLogs(null, LogLevel.INFO, message, source, operation, null);
  }

  public static void warn(String message, String source, String operation) {
    addLogs(null, LogLevel.WARN, message, source, operation, null);
  }

  public static void error(String message, String source, String operation) {
    addLogs(null, LogLevel.ERROR, message, source, operation, null);
  }

  public static void error(
    Exception exceptionValue,
    String source,
    String operation
  ) {
    if (exceptionValue == null) {
      throw new LogServiceException('Exception must not be null.');
    }

    addLogs(
      null,
      LogLevel.ERROR,
      exceptionValue.getMessage(),
      source,
      operation,
      exceptionValue.getStackTraceString()
    );
  }

  public static void critical(String message, String source, String operation) {
    addLogs(null, LogLevel.CRITICAL, message, source, operation, null);
  }

  /*
   * Persists buffered logs.
   *
   * If an unexpected exception occurs, the snapshot is
   * restored to the buffer.
   */
  public static List<Database.SaveResult> insertLogs() {
    if (logBuffer.isEmpty()) {
      return new List<Database.SaveResult>();
    }

    List<LogEntry> entriesToPublish = new List<LogEntry>(logBuffer);
    List<Database.SaveResult> results;

    try {
      results = sink.save(entriesToPublish);
    } catch (Exception ex) {
      // Keep the complete buffer available for retry.
      throw ex;
    }

    List<LogEntry> failedEntries = new List<LogEntry>();

    for (Integer index = 0; index < results.size(); index++) {
      if (!results[index].isSuccess()) {
        failedEntries.add(entriesToPublish[index]);
      }
    }
    logBuffer.clear();
    logBuffer.addAll(failedEntries);
    return results;
  }

  /*
   * Returns the number of logs currently waiting
   * to be persisted.
   */
  public static Integer getBufferedLogCount() {
    return logBuffer.size();
  }

  /*
   * Clears buffered logs without inserting them.
   */
  public static void clearLogs() {
    logBuffer.clear();
  }

  /*
   * Internal generic method used by all log-level methods.
   *
   * Builds logs and adds them to the buffer.
   */
  private static void addLogs(
    List<SObject> records,
    LogLevel level,
    String message,
    String source,
    String operation,
    String stackTrace
  ) {
    validateArguments(level, message, source, operation);

    logBuffer.addAll(
      buildLogs(records, level, message, source, operation, stackTrace)
    );
  }

  /*
   * Builds logs without performing DML.
   */
  @TestVisible
  private static List<LogEntry> buildLogs(
    List<SObject> records,
    LogLevel level,
    String message,
    String source,
    String operation,
    String stackTrace
  ) {
    List<LogEntry> entries = new List<LogEntry>();

    /*
     * System log
     */
    if (records == null || records.isEmpty()) {
      entries.add(
        new LogEntry(level, message, source, operation, null, stackTrace)
      );

      return entries;
    }

    /*
     * Record-related logs
     */
    Boolean hasValidRecord = false;

    for (SObject record : records) {
      if (record == null) {
        continue;
      }

      hasValidRecord = true;

      entries.add(
        new LogEntry(level, message, source, operation, record.Id, stackTrace)
      );
    }

    /*
     * All items were null.
     * Fallback to a system log.
     */
    if (!hasValidRecord) {
      entries.add(
        new LogEntry(level, message, source, operation, null, stackTrace)
      );
    }

    return entries;
  }

  private static void validateArguments(
    LogLevel level,
    String message,
    String source,
    String operation
  ) {
    if (level == null) {
      throw new LogServiceException('Log level must not be null.');
    }

    if (String.isBlank(message)) {
      throw new LogServiceException('Log message must not be blank.');
    }

    if (String.isBlank(source)) {
      throw new LogServiceException('Log source must not be blank.');
    }

    if (String.isBlank(operation)) {
      throw new LogServiceException('Log operation must not be blank.');
    }
  }

  private static String getTransactionId() {
    if (Request.getCurrent() == null) {
      return null;
    }

    return Request.getCurrent().getRequestId();
  }

  public class LogServiceException extends Exception {
  }
}
