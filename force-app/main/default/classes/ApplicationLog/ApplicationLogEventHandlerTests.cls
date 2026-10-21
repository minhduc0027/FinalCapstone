@IsTest
private class ApplicationLogEventHandlerTests {
  /*
   * Chọn Level hợp lệ nếu Level__c là restricted picklist.
   */
  private static String getValidLevel() {
    Schema.DescribeFieldResult fieldDescribe = Application_Log__c.Level__c.getDescribe();

    if (fieldDescribe.getType() == Schema.DisplayType.PICKLIST) {
      for (Schema.PicklistEntry entry : fieldDescribe.getPicklistValues()) {
        if (entry.isActive()) {
          return entry.getValue();
        }
      }
    }

    return 'INFO';
  }

  private static Application_Log_Event__e createEvent(String eventKey) {
    return new Application_Log_Event__e(
      Event_Key__c = eventKey,
      Level__c = getValidLevel(),
      Message__c = 'Handler unit test',
      Source__c = 'HandlerTest',
      Operation__c = 'handle',
      Transaction_Id__c = 'test-transaction',
      UserId__c = String.valueOf(UserInfo.getUserId()),
      Stack_Trace__c = 'Test stack trace',
      Logged_At__c = System.now()
    );
  }

  @IsTest
  static void handle_shouldIgnoreNullAndEmptyInput() {
    Test.startTest();

    Integer queriesBefore = Limits.getQueries();
    Integer dmlBefore = Limits.getDmlStatements();

    ApplicationLogEventHandler.handle(null);

    ApplicationLogEventHandler.handle(new List<Application_Log_Event__e>());

    System.assertEquals(
      queriesBefore,
      Limits.getQueries(),
      'Null/empty input must not execute SOQL.'
    );

    System.assertEquals(
      dmlBefore,
      Limits.getDmlStatements(),
      'Null/empty input must not execute DML.'
    );

    Test.stopTest();
  }

  @IsTest
  static void handle_shouldMapEventFields() {
    Application_Log_Event__e eventRecord = createEvent('mapping-key');

    /*
     * RelatedRecord__c để null trong test mapping.
     * Test Id không hợp lệ nằm ở method riêng.
     */
    eventRecord.RelatedRecord__c = null;

    Test.startTest();

    ApplicationLogEventHandler.handle(
      new List<Application_Log_Event__e>{ eventRecord }
    );

    Test.stopTest();

    List<Application_Log__c> logs = [
      SELECT
        Level__c,
        Message__c,
        Source__c,
        Operation__c,
        RelatedRecord__c,
        Transaction_Id__c,
        UserId__c,
        Stack_Trace__c,
        Event_Key__c,
        Logged_At__c
      FROM Application_Log__c
      WHERE Event_Key__c = 'mapping-key'
    ];

    System.assertEquals(1, logs.size(), 'Exactly one log must be inserted.');

    Application_Log__c actual = logs[0];

    System.assertEquals(eventRecord.Level__c, actual.Level__c);
    System.assertEquals(eventRecord.Message__c, actual.Message__c);
    System.assertEquals(eventRecord.Source__c, actual.Source__c);
    System.assertEquals(eventRecord.Operation__c, actual.Operation__c);
    System.assertEquals(null, actual.RelatedRecord__c);
    System.assertEquals(
      eventRecord.Transaction_Id__c,
      actual.Transaction_Id__c
    );
    System.assertEquals(
      String.valueOf(UserInfo.getUserId()),
      String.valueOf(actual.UserId__c)
    );
    System.assertEquals(eventRecord.Stack_Trace__c, actual.Stack_Trace__c);
    System.assertEquals(eventRecord.Event_Key__c, actual.Event_Key__c);
    System.assertEquals(eventRecord.Logged_At__c, actual.Logged_At__c);
  }

  @IsTest
  static void handle_shouldSkipPreviouslyProcessedEvent() {
    Application_Log_Event__e eventRecord = createEvent('existing-key');

    // Tạo log bằng lần xử lý đầu tiên.
    ApplicationLogEventHandler.handle(
      new List<Application_Log_Event__e>{ eventRecord }
    );

    List<Application_Log__c> initialLogs = [
      SELECT Id, Message__c
      FROM Application_Log__c
      WHERE Event_Key__c = 'existing-key'
    ];

    System.assertEquals(
      1,
      initialLogs.size(),
      'Initial log must exist before testing deduplication.'
    );

    eventRecord.Message__c = 'Duplicate must not overwrite original';

    Test.startTest();

    Integer dmlBefore = Limits.getDmlStatements();

    ApplicationLogEventHandler.handle(
      new List<Application_Log_Event__e>{ eventRecord }
    );

    System.assertEquals(
      dmlBefore,
      Limits.getDmlStatements(),
      'An entirely duplicated batch must not execute DML.'
    );

    Test.stopTest();

    List<Application_Log__c> finalLogs = [
      SELECT Id, Message__c
      FROM Application_Log__c
      WHERE Event_Key__c = 'existing-key'
    ];

    System.assertEquals(1, finalLogs.size());

    System.assertEquals(initialLogs[0].Id, finalLogs[0].Id);

    System.assertEquals(
      initialLogs[0].Message__c,
      finalLogs[0].Message__c,
      'Existing log must remain unchanged.'
    );
  }

  @IsTest
  static void handle_shouldInsertNewEventAndSkipExistingEvent() {
    Application_Log_Event__e existingEvent = createEvent('mixed-existing');

    ApplicationLogEventHandler.handle(
      new List<Application_Log_Event__e>{ existingEvent }
    );

    System.assertEquals(
      1,
      [
        SELECT COUNT()
        FROM Application_Log__c
        WHERE Event_Key__c = 'mixed-existing'
      ]
    );

    Application_Log_Event__e newEvent = createEvent('mixed-new');

    Test.startTest();

    ApplicationLogEventHandler.handle(
      new List<Application_Log_Event__e>{ existingEvent, newEvent }
    );

    Test.stopTest();

    System.assertEquals(
      1,
      [
        SELECT COUNT()
        FROM Application_Log__c
        WHERE Event_Key__c = 'mixed-existing'
      ],
      'Existing event must not create another log.'
    );

    System.assertEquals(
      1,
      [
        SELECT COUNT()
        FROM Application_Log__c
        WHERE Event_Key__c = 'mixed-new'
      ],
      'New event must create a log.'
    );
  }

  @IsTest
  static void handle_shouldConvertInvalidIdsToNull() {
    Application_Log_Event__e eventRecord = createEvent('invalid-ids');

    eventRecord.RelatedRecord__c = 'invalid-id';
    eventRecord.UserId__c = 'invalid-user-id';

    Test.startTest();

    ApplicationLogEventHandler.handle(
      new List<Application_Log_Event__e>{ eventRecord }
    );

    Test.stopTest();

    List<Application_Log__c> logs = [
      SELECT RelatedRecord__c, UserId__c
      FROM Application_Log__c
      WHERE Event_Key__c = 'invalid-ids'
    ];

    System.assertEquals(
      1,
      logs.size(),
      'Invalid Id strings must not prevent log creation.'
    );

    System.assertEquals(null, logs[0].RelatedRecord__c);

    System.assertEquals(null, logs[0].UserId__c);
  }

  @IsTest
  static void handle_shouldAcceptBlankIdsAndMissingEventKeys() {
    Application_Log_Event__e firstEvent = createEvent(null);

    firstEvent.RelatedRecord__c = null;
    firstEvent.UserId__c = null;
    firstEvent.Message__c = 'No key - first';

    Application_Log_Event__e secondEvent = createEvent(null);

    secondEvent.RelatedRecord__c = '   ';
    secondEvent.UserId__c = '   ';
    secondEvent.Message__c = 'No key - second';

    Set<String> messages = new Set<String>{
      firstEvent.Message__c,
      secondEvent.Message__c
    };

    Test.startTest();

    Integer queriesBefore = Limits.getQueries();

    ApplicationLogEventHandler.handle(
      new List<Application_Log_Event__e>{ firstEvent, secondEvent }
    );

    /*
     * Không assert query count ở đây vì trigger/flow trên
     * Application_Log__c có thể thực hiện SOQL.
     */
    Test.stopTest();

    List<Application_Log__c> logs = [
      SELECT Event_Key__c, RelatedRecord__c, UserId__c
      FROM Application_Log__c
    ];

    System.assertEquals(
      2,
      logs.size(),
      'Events without keys should still create logs.'
    );

    for (Application_Log__c logRecord : logs) {
      System.assert(String.isBlank(logRecord.Event_Key__c));
      System.assertEquals(null, logRecord.RelatedRecord__c);
      System.assertEquals(null, logRecord.UserId__c);
    }
  }

  @IsTest
  static void handle_shouldProcessBulkEvents() {
    List<Application_Log_Event__e> events = new List<Application_Log_Event__e>();

    Set<String> expectedKeys = new Set<String>();

    for (Integer index = 0; index < 200; index++) {
      String eventKey = 'bulk-' + index;

      expectedKeys.add(eventKey);
      events.add(createEvent(eventKey));
    }

    Test.startTest();

    ApplicationLogEventHandler.handle(events);

    Test.stopTest();

    List<Application_Log__c> logs = [
      SELECT Event_Key__c
      FROM Application_Log__c
      WHERE Event_Key__c IN :expectedKeys
    ];

    System.assertEquals(200, logs.size(), 'Every event must create a log.');

    Set<String> actualKeys = new Set<String>();

    for (Application_Log__c logRecord : logs) {
      actualKeys.add(logRecord.Event_Key__c);
    }

    System.assertEquals(
      expectedKeys,
      actualKeys,
      'Inserted keys must match the input batch.'
    );
  }
}
