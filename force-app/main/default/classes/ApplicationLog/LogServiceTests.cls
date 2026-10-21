@IsTest
private class LogServiceTests {
  private class SinkTestException extends Exception {
  }

  /*
   * Mock persistence:
   * - Ghi nhận entries nhận được.
   * - Giả lập success/failure theo index.
   * - Có thể throw exception để test retry.
   */
  private class MockLogSink implements LogService.LogSink {
    public Integer calls = 0;

    public Boolean shouldThrow = false;

    public Set<Integer> failedIndexes = new Set<Integer>();

    public List<LogService.LogEntry> received = new List<LogService.LogEntry>();

    public List<Database.SaveResult> save(List<LogService.LogEntry> entries) {
      calls++;

      received = new List<LogService.LogEntry>(entries);

      if (shouldThrow) {
        throw new SinkTestException('Simulated sink failure');
      }

      List<Database.SaveResult> results = new List<Database.SaveResult>();

      for (Integer index = 0; index < entries.size(); index++) {
        Boolean success = !failedIndexes.contains(index);

        results.add(
          (Database.SaveResult) JSON.deserialize(
            '{"success":' + String.valueOf(success) + ',"errors":[]}',
            Database.SaveResult.class
          )
        );
      }

      return results;
    }
  }

  private static MockLogSink installMock() {
    LogService.clearLogs();

    MockLogSink mock = new MockLogSink();
    LogService.sink = mock;

    return mock;
  }

  /*
   * Không cần insert Case.
   * LogService chỉ đọc record.Id.
   */
  private static List<SObject> relatedRecords() {
    return new List<SObject>{
      new Case(Id = (Id) '500000000000001'),
      null,
      new Case(Id = (Id) '500000000000002')
    };
  }

  private static Exception createException() {
    try {
      Integer zero = 0;
      Integer result = 1 / zero;
    } catch (Exception ex) {
      return ex;
    }

    return null;
  }

  private static String makeText(Integer length) {
    String value = 'x';

    while (value.length() < length) {
      value += value;
    }

    return value.substring(0, length);
  }

  /*
   * =========================================================
   * LogEntry constructor
   * =========================================================
   */

  @IsTest
  static void logEntry_shouldPopulateMetadata() {
    Datetime beforeCreation = Datetime.now();

    Id relatedId = (Id) '500000000000001';

    LogService.LogEntry first = new LogService.LogEntry(
      LogService.LogLevel.ERROR,
      'Test message',
      'LogServiceTest',
      'constructor',
      relatedId,
      'Test stack trace'
    );

    LogService.LogEntry second = new LogService.LogEntry(
      LogService.LogLevel.INFO,
      'Second message',
      'LogServiceTest',
      'constructor',
      null,
      null
    );

    System.assertEquals(LogService.LogLevel.ERROR, first.level);
    System.assertEquals('Test message', first.message);
    System.assertEquals('LogServiceTest', first.source);
    System.assertEquals('constructor', first.operation);
    System.assertEquals(relatedId, first.relatedRecordId);
    System.assertEquals('Test stack trace', first.stackTrace);
    System.assertEquals(UserInfo.getUserId(), first.userId);

    System.assertNotEquals(null, first.loggedAt);
    System.assert(first.loggedAt >= beforeCreation);

    System.assert(String.isNotBlank(first.eventKey));
    System.assertNotEquals(first.eventKey, second.eventKey);

    System.assertEquals(
      first.transactionId,
      second.transactionId,
      'Entries in the same transaction must share transactionId.'
    );

    if (Request.getCurrent() != null) {
      System.assertEquals(
        Request.getCurrent().getRequestId(),
        first.transactionId
      );
    }
  }

  /*
   * =========================================================
   * Public logging methods: system logs
   * =========================================================
   */

  @IsTest
  static void systemMethods_shouldBufferAllLevelsWithoutDml() {
    MockLogSink mock = installMock();

    Integer dmlBefore = Limits.getDmlStatements();
    Integer queriesBefore = Limits.getQueries();

    LogService.info('Info message', 'LogServiceTest', 'system');
    LogService.warn('Warn message', 'LogServiceTest', 'system');
    LogService.error('Error message', 'LogServiceTest', 'system');
    LogService.critical('Critical message', 'LogServiceTest', 'system');

    System.assertEquals(4, LogService.getBufferedLogCount());

    System.assertEquals(
      dmlBefore,
      Limits.getDmlStatements(),
      'Logging methods must not perform DML.'
    );
    System.assertEquals(
      queriesBefore,
      Limits.getQueries(),
      'Logging methods must not perform SOQL.'
    );
    System.assertEquals(
      0,
      mock.calls,
      'Sink must not run before insertLogs().'
    );

    List<LogService.LogLevel> expectedLevels = new List<LogService.LogLevel>{
      LogService.LogLevel.INFO,
      LogService.LogLevel.WARN,
      LogService.LogLevel.ERROR,
      LogService.LogLevel.CRITICAL
    };

    for (Integer index = 0; index < 4; index++) {
      LogService.LogEntry entry = LogService.logBuffer[index];

      System.assertEquals(expectedLevels[index], entry.level);
      System.assertEquals(null, entry.relatedRecordId);
      System.assertEquals(null, entry.stackTrace);
    }
  }

  /*
   * =========================================================
   * Public logging methods: record-related logs
   * =========================================================
   */

  @IsTest
  static void recordMethods_shouldSkipNullRecords() {
    installMock();

    List<SObject> records = relatedRecords();

    LogService.info(records, 'Info', 'LogServiceTest', 'records');
    LogService.warn(records, 'Warn', 'LogServiceTest', 'records');
    LogService.error(records, 'Error', 'LogServiceTest', 'records');
    LogService.critical(records, 'Critical', 'LogServiceTest', 'records');

    System.assertEquals(
      8,
      LogService.getBufferedLogCount(),
      'Each method must create two logs, skipping null.'
    );

    List<LogService.LogLevel> expectedLevels = new List<LogService.LogLevel>{
      LogService.LogLevel.INFO,
      LogService.LogLevel.WARN,
      LogService.LogLevel.ERROR,
      LogService.LogLevel.CRITICAL
    };

    for (Integer groupIndex = 0; groupIndex < 4; groupIndex++) {
      Integer firstIndex = groupIndex * 2;

      System.assertEquals(
        expectedLevels[groupIndex],
        LogService.logBuffer[firstIndex].level
      );
      System.assertEquals(
        expectedLevels[groupIndex],
        LogService.logBuffer[firstIndex + 1].level
      );

      System.assertEquals(
        records[0].Id,
        LogService.logBuffer[firstIndex].relatedRecordId
      );
      System.assertEquals(
        records[2].Id,
        LogService.logBuffer[firstIndex + 1].relatedRecordId
      );
    }
  }

  @IsTest
  static void buildLogs_shouldHandleEmptyAndNullRecords() {
    installMock();

    List<LogService.LogEntry> emptyInput = LogService.buildLogs(
      new List<SObject>(),
      LogService.LogLevel.INFO,
      'Empty input',
      'LogServiceTest',
      'build',
      null
    );

    List<LogService.LogEntry> allNullInput = LogService.buildLogs(
      new List<SObject>{ null, null },
      LogService.LogLevel.WARN,
      'All null',
      'LogServiceTest',
      'build',
      'stack'
    );

    List<LogService.LogEntry> unsavedInput = LogService.buildLogs(
      new List<SObject>{ new Case(Subject = 'Unsaved') },
      LogService.LogLevel.INFO,
      'Unsaved record',
      'LogServiceTest',
      'build',
      null
    );

    System.assertEquals(1, emptyInput.size());
    System.assertEquals(null, emptyInput[0].relatedRecordId);

    System.assertEquals(1, allNullInput.size());
    System.assertEquals(null, allNullInput[0].relatedRecordId);
    System.assertEquals('stack', allNullInput[0].stackTrace);

    System.assertEquals(1, unsavedInput.size());
    System.assertEquals(null, unsavedInput[0].relatedRecordId);

    System.assertEquals(
      0,
      LogService.getBufferedLogCount(),
      'buildLogs() must not modify the buffer.'
    );
  }

  /*
   * =========================================================
   * Exception overloads
   * =========================================================
   */

  @IsTest
  static void errorExceptionOverloads_shouldCaptureException() {
    installMock();

    Exception original = createException();

    System.assertNotEquals(null, original);

    LogService.error(original, 'LogServiceTest', 'systemException');

    LogService.error(
      relatedRecords(),
      original,
      'LogServiceTest',
      'recordException'
    );

    System.assertEquals(3, LogService.getBufferedLogCount());

    for (LogService.LogEntry entry : LogService.logBuffer) {
      System.assertEquals(LogService.LogLevel.ERROR, entry.level);
      System.assertEquals(original.getMessage(), entry.message);
      System.assertEquals(original.getStackTraceString(), entry.stackTrace);
    }

    System.assertEquals(null, LogService.logBuffer[0].relatedRecordId);
    System.assertNotEquals(null, LogService.logBuffer[1].relatedRecordId);
  }

  @IsTest
  static void errorExceptionOverloads_shouldRejectNullException() {
    installMock();

    try {
      LogService.error((Exception) null, 'LogServiceTest', 'systemException');

      System.assert(false, 'Expected LogServiceException.');
    } catch (LogService.LogServiceException ex) {
      System.assertEquals('Exception must not be null.', ex.getMessage());
    }

    try {
      LogService.error(
        new List<SObject>(),
        (Exception) null,
        'LogServiceTest',
        'recordException'
      );

      System.assert(false, 'Expected LogServiceException.');
    } catch (LogService.LogServiceException ex) {
      System.assertEquals('Exception must not be null.', ex.getMessage());
    }

    System.assertEquals(0, LogService.getBufferedLogCount());
  }

  /*
   * =========================================================
   * Argument validation
   * =========================================================
   */

  @IsTest
  static void logging_shouldRejectBlankArguments() {
    installMock();

    try {
      LogService.info('   ', 'LogServiceTest', 'validation');
      System.assert(false, 'Expected blank message error.');
    } catch (LogService.LogServiceException ex) {
      System.assertEquals('Log message must not be blank.', ex.getMessage());
    }

    try {
      LogService.warn('Message', null, 'validation');
      System.assert(false, 'Expected blank source error.');
    } catch (LogService.LogServiceException ex) {
      System.assertEquals('Log source must not be blank.', ex.getMessage());
    }

    try {
      LogService.critical('Message', 'LogServiceTest', '');
      System.assert(false, 'Expected blank operation error.');
    } catch (LogService.LogServiceException ex) {
      System.assertEquals('Log operation must not be blank.', ex.getMessage());
    }

    System.assertEquals(0, LogService.getBufferedLogCount());
  }

  /*
   * =========================================================
   * insertLogs: empty buffer
   * =========================================================
   */

  @IsTest
  static void insertLogs_shouldNotCallSinkForEmptyBuffer() {
    MockLogSink mock = installMock();

    List<Database.SaveResult> results = LogService.insertLogs();

    System.assertNotEquals(null, results);
    System.assertEquals(0, results.size());
    System.assertEquals(0, mock.calls);
  }

  /*
   * =========================================================
   * insertLogs: success
   * =========================================================
   */

  @IsTest
  static void insertLogs_shouldClearSuccessfulEntries() {
    MockLogSink mock = installMock();

    LogService.info('First', 'LogServiceTest', 'save');
    LogService.warn('Second', 'LogServiceTest', 'save');

    String firstKey = LogService.logBuffer[0].eventKey;
    String secondKey = LogService.logBuffer[1].eventKey;

    List<Database.SaveResult> results = LogService.insertLogs();

    System.assertEquals(1, mock.calls);
    System.assertEquals(2, mock.received.size());
    System.assertEquals(2, results.size());

    System.assert(results[0].isSuccess());
    System.assert(results[1].isSuccess());

    System.assertEquals(firstKey, mock.received[0].eventKey);
    System.assertEquals(secondKey, mock.received[1].eventKey);

    System.assertEquals(0, LogService.getBufferedLogCount());

    LogService.insertLogs();

    System.assertEquals(
      1,
      mock.calls,
      'A second flush of an empty buffer must not call sink.'
    );
  }

  /*
   * =========================================================
   * insertLogs: partial failure + retry
   * =========================================================
   */

  @IsTest
  static void insertLogs_shouldKeepOnlyFailedEntriesForRetry() {
    MockLogSink mock = installMock();
    mock.failedIndexes.add(1);

    LogService.info('First', 'LogServiceTest', 'partial');
    LogService.error('Second', 'LogServiceTest', 'partial');
    LogService.warn('Third', 'LogServiceTest', 'partial');

    String failedKey = LogService.logBuffer[1].eventKey;

    List<Database.SaveResult> results = LogService.insertLogs();

    System.assertEquals(3, results.size());
    System.assert(results[0].isSuccess());
    System.assertEquals(false, results[1].isSuccess());
    System.assert(results[2].isSuccess());

    System.assertEquals(1, LogService.getBufferedLogCount());
    System.assertEquals('Second', LogService.logBuffer[0].message);
    System.assertEquals(
      failedKey,
      LogService.logBuffer[0].eventKey,
      'Retry must preserve the original event key.'
    );

    mock.failedIndexes.clear();

    List<Database.SaveResult> retryResults = LogService.insertLogs();

    System.assertEquals(2, mock.calls);
    System.assertEquals(1, mock.received.size());
    System.assertEquals(failedKey, mock.received[0].eventKey);

    System.assertEquals(1, retryResults.size());
    System.assert(retryResults[0].isSuccess());
    System.assertEquals(0, LogService.getBufferedLogCount());
  }

  /*
   * =========================================================
   * insertLogs: unexpected exception + retry
   * =========================================================
   */

  @IsTest
  static void insertLogs_shouldPreserveBufferWhenSinkThrows() {
    MockLogSink mock = installMock();
    mock.shouldThrow = true;

    LogService.info('First', 'LogServiceTest', 'exception');
    LogService.error('Second', 'LogServiceTest', 'exception');

    String firstKey = LogService.logBuffer[0].eventKey;
    String secondKey = LogService.logBuffer[1].eventKey;

    try {
      LogService.insertLogs();

      System.assert(false, 'Expected sink exception.');
    } catch (SinkTestException ex) {
      System.assertEquals('Simulated sink failure', ex.getMessage());
    }

    System.assertEquals(2, LogService.getBufferedLogCount());
    System.assertEquals(firstKey, LogService.logBuffer[0].eventKey);
    System.assertEquals(secondKey, LogService.logBuffer[1].eventKey);

    mock.shouldThrow = false;

    List<Database.SaveResult> results = LogService.insertLogs();

    System.assertEquals(2, results.size());
    System.assertEquals(0, LogService.getBufferedLogCount());
    System.assertEquals(2, mock.calls);
  }

  /*
   * =========================================================
   * clearLogs
   * =========================================================
   */

  @IsTest
  static void clearLogs_shouldDiscardBufferWithoutSaving() {
    MockLogSink mock = installMock();

    LogService.info('First', 'LogServiceTest', 'clear');
    LogService.warn('Second', 'LogServiceTest', 'clear');

    System.assertEquals(2, LogService.getBufferedLogCount());

    LogService.clearLogs();

    System.assertEquals(0, LogService.getBufferedLogCount());
    System.assertEquals(0, mock.calls);

    // Clearing an already empty buffer is safe.
    LogService.clearLogs();

    System.assertEquals(0, LogService.getBufferedLogCount());
  }

  /*
   * =========================================================
   * Real PlatformEventLogSink
   *
   * Không thay sink bằng mock trong test method này.
   * Mỗi test method có static state riêng.
   * =========================================================
   */

  @IsTest
  static void platformEventSink_shouldPublishAndTruncate() {
    LogService.clearLogs();

    // Bao phủ events.isEmpty() trong sink thật.
    List<Database.SaveResult> emptyResults = LogService.sink.save(
      new List<LogService.LogEntry>()
    );

    System.assertEquals(0, emptyResults.size());

    String longText = makeText(32768);

    LogService.LogEntry longEntry = new LogService.LogEntry(
      LogService.LogLevel.ERROR,
      longText,
      makeText(256),
      makeText(101),
      null,
      longText
    );

    /*
     * Gọi constructor trực tiếp để kiểm tra nhánh
     * truncate(null), không qua argument validation.
     */
    LogService.LogEntry nullEntry = new LogService.LogEntry(
      LogService.LogLevel.INFO,
      null,
      'Source',
      null,
      null,
      null
    );

    LogService.LogEntry shortEntry = new LogService.LogEntry(
      LogService.LogLevel.WARN,
      'Short message',
      'LogServiceTest',
      'publish',
      null,
      'Short stack'
    );

    Test.startTest();

    List<Database.SaveResult> results = LogService.sink.save(
      new List<LogService.LogEntry>{ longEntry, nullEntry, shortEntry }
    );

    System.assertEquals(3, results.size());

    for (Database.SaveResult result : results) {
      System.assert(
        result.isSuccess(),
        'Platform Event publish request failed: ' +
        JSON.serialize(result.getErrors())
      );
    }

    Test.stopTest();

    /*
     * Sink tạo event mới, không được thay đổi LogEntry gốc.
     */
    System.assertEquals(32768, longEntry.message.length());
    System.assertEquals(256, longEntry.source.length());
    System.assertEquals(101, longEntry.operation.length());
    System.assertEquals(32768, longEntry.stackTrace.length());
  }
}
